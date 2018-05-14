package SQS::Worker::CloudFormationResource {
  our $VERSION = '0.01';
  use Moose::Role;

  requires 'create_resource';
  requires 'update_resource';
  requires 'delete_resource';

  use SQS::Worker::CloudFormationResourceException;
  use SQS::Worker::CloudFormationResource::Request;
  use SQS::Worker::CloudFormationResource::Response;

  use Furl;
  use IO::Socket::SSL;
  use JSON::MaybeXS qw/decode_json/;

  # Id used to signal that a resource creation has failed
  use constant FAILED_CREATION_ID => 'FAILEDRESOURCECREATE';

  has http_client => (is => 'ro', lazy => 1, default => sub {
    return Furl->new(
      ssl_opts => {
        SSL_verify_mode => SSL_VERIFY_PEER(),
      },
    );
  });

  sub process_message {
    my ($self, $sns) = @_;

    SQS::Worker::CloudFormationResourceException->throw(
      "SQS::Worker::CloudFormationResource only knows how to process SNS::Notification objects. Does your worker also consume SQS::Worker::SNS?"
    ) if (not $sns->isa('SNS::Notification'));
 
    my $json_message = decode_json($sns->Message);

    # ServiceToken gets sent by CloudFormation in the ResourceProperties because it's
    # specified in the properties of the template, but is of no relevance to the 
    # custom resource worker
    delete $json_message->{ ResourceProperties }->{ ServiceToken };
    my $req = SQS::Worker::CloudFormationResource::Request->new($json_message);

    # Initialize the response to sane values (so the processor doesn't have
    # to worry about setting them correctly in the *_resource methods
    my $res = SQS::Worker::CloudFormationResource::Response->new(
      StackId => $req->StackId,
      RequestId => $req->RequestId,
      LogicalResourceId => $req->LogicalResourceId
    );

    if ($req->RequestType eq 'Create') {
      $self->log->info(
        sprintf "%s create_resource for stack %s logical id: %s", 
          $req->RequestId,
          $req->StackId,
          $req->LogicalResourceId
      );
      eval {
        $self->create_resource($req, $res);
        $res->PhysicalResourceId(FAILED_CREATION_ID) if (not defined $res->PhysicalResourceId and $res->Status eq 'FAILED');
        SQS::Worker::CloudFormationResourceException->throw(
          "No PhysicalResourceId was assigned to the response in the create_resource call"
        ) if (not defined $res->PhysicalResourceId);
        SQS::Worker::CloudFormationResourceException->throw(
          "No Status was assigned to the response"
        ) if (not defined $res->Status);
      };
      if ($@) {
        $self->log->error($@);
        $res->set_failed('Creation failed due to an unhandled internal error');
        $res->PhysicalResourceId(FAILED_CREATION_ID);
      }
      $self->log->info(sprintf "created physical id: %s", $res->PhysicalResourceId);
    } elsif ($req->RequestType eq 'Update') {
      $self->log->info(
        sprintf "%s update_resource for stack %s logical id: %s physical id %s",
          $req->RequestId,
          $req->StackId,
          $req->LogicalResourceId,
          $req->PhysicalResourceId,
      );
      eval {
        $self->update_resource($req, $res);
      };
      if ($@) {
        $self->log->error($@);
        $res->set_failed('Update failed due to an unhandled internal error');
      }
    } elsif ($req->RequestType eq 'Delete') {
      $self->log->info(
        sprintf "%s create_resource for stack %s logical id: %s physical id %s",
          $req->RequestId,
          $req->StackId,
          $req->LogicalResourceId,
          $req->PhysicalResourceId,
      );

      # Assign the PhysicalResourceId for the response, as DELETE needs this 
      # even if the resource fails or succeeds creation
      $res->PhysicalResourceId($req->PhysicalResourceId);

      # When a create fails, and cloudformation rolls back, it sends a
      # DELETE for that rolled back item
      if ($req->PhysicalResourceId eq FAILED_CREATION_ID) {
        $self->log->info("Rollback detected. Skipping delete");
        $res->set_success('Rollback approved');
      } else {
        eval {
          $self->delete_resource($req, $res);
        };
        if ($@) {
          $self->log->error($@);
          $res->set_failed('Delete failed due to an unhandled internal error');
        }
      }
    } else {
      SQS::Worker::CloudFormationResourceException->throw("Unrecognized RequestType " . $req->RequestType);
    }

    $self->log->info(sprintf 'action status %s reason %s', $res->Status, ($res->Reason // '[none specified]'));

    # return the response to CloudFormation via the presigned URL that they
    # send you in the message
    $self->http_client->put(
      $req->ResponseURL,
      ['Content-Type' => ''],
      $res->to_json,
    );
  };
}
1;

=head1 NAME

SQS::Worker::CloudFormationResource - A helper to develop your own custom CloudFormation resources

=head1 DESCRIPTION

This is a L<SQS::Worker> role that helps you develop SNS-based CloudFormation Custom Resources that deliver to an
SQS queue.

More information on SNS based Custom Resources here: L<https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-sns.html>

This module takes care of lots of repetitive work when building an SNS-based CloudFormation Custom Resource.

=head1 USAGE

  package MyCustomResource {
    use Moose;
    with 'SQS::Worker', 'SQS::Worker::SNS', 'SQS::Worker::CloudFormationResource';

    sub create_resource {
      my ($self, $request, $result) = @_;
      # $request is a SQS::Worker::CloudFormationResource::Request
      # $result  is a SQS::Worker::CloudFormationResource::Response
    }

    sub update_resource {
      my ($self, $request, $result) = @_;
    }

    sub delete_resource {
      my ($self, $request, $result) = @_;
    }
  }

=head1 WRITING A CUSTOM RESOURCE

The worker will poll the SQS queue for you, invoking C<create_resource>, C<update_resource>
or C<delete_resource> in function of what is happening in CloudFormation, passing them a 
request object with all the information coming from CloudFormation. Look at L<SQS::Worker::CloudFormationResource::Request>
for more information on what information a request has. result is an object that has L<SQS::Worker::CloudFormationResource::Response>.
Set the appropiate properties of the response object. The response object will be returned to CloudFormation.

  $result->set_success('Created resource'); # the success message will show in the cloudformation log
  $result->PhysicalResourceId('resource-123456');
  $result->Data({
    Color => 'Blue',
  });

When calling update_resource: C<PhysicalResourceId> will already be initialized to the PhisicalResourceId that was set in C<create_resource>,
meaning that if it isn't updated, CloudFormation considers the update as a in-place replacement. If a new C<PhysicalResourceId> is assigned,
CloudFormation considers the operation as a replacement. Later on, CloudFormation will send a Delete for the old PhysicalResourceId, which
shouldn't be handled as any special case: the C<delete_resource> will be invoked.

Unhandled exceptions in any C<resource_*> methods will be handled, returning a generic "Internal Error" text to CloudFormation,
considering the resource FAILED.

Unhandled exceptions in C<resource_create> will treat the resource creation as a special case. Since CloudFormation requires a Physical ID to
be sent, even if we're signalling a FAILURE, SQS::Worker::CloudFormationResource will use an internal Physical ID, that will never be delivered
to the C<delete_resource> method (it will be intercepted and dropped before getting processed).

=head1 SETTING UP A CUSTOM RESOURCE

To use the resource in CloudFormation, you have to provision an SNS topic that delivers it's messages
to an SQS queue. You can setup an SNS topic with the bundled C<examples/sns-topic-for-cloudformation.json> file (which will output
all the data you need to run the worker

  spawn_worker --worker CustomResourceExample1 --queue_url=http://..../QueueURL --region=eu-west-1 --log_conf log.conf

=head1 USING YOUR CUSTOM RESOURCE

  { "resources": [
    "Custom1": {
      "Type": "Custom::MyCustomResource",
      "Version": "1.0",
      "Properties": {
        "ServiceToken": "arn:of the SNS topic for the custom resource",
        ... Resource Properties ...
      }
    }
  ] }

The data you have set in the C<Data> property of the response object will be accessible in CloudFormation templates via the GetAtt
function.

  { "Fn::GetAtt": [ "Custom1", "Color" ] }

=head1 METHODS

=head2 create_resource($request, $response)

Implement this method in your Custom Resource worker class. All properties sent by CloudFormation will be in C<$request> of type 
L<SQS::Worker::CloudFormationResource::Request>. This method should modify C<$response> to control what will be sent to CloudFormation.
The following can be done:

Either call C<set_success> or C<set_failed>

Set attribute C<PhysicalResourceId> (C<$response-&gt;('resource-123456');>)

Set attribute C<Data> to a Hashref with the keys and values that CloudFormation will treat as this objects attributes

=head2 update_resource

Implement this method in your Custom Resource worker class.

=head2 delete_resource

Implement this method in your Custom Resource worker class.

Either call C<set_success> or C<set_failed> to indicate that the resource was deleted or not

=head1 SEE ALSO

L<SQS::Worker>

L<https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources-sns.html>

L<Paws::SQS>

=head1 COPYRIGHT and LICENSE

Copyright (c) 2018 by CAPSiDE

This code is distributed under the Apache 2 License. The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHORS

  Jose Luis Martinez
  JLMARTIN
  jlmartinez@capside.com

=cut
