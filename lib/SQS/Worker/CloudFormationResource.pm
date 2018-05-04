package SQS::Worker::CloudFormationResource {
  our $VERSION = '0.01';
  use Moose::Role;

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
      eval {
        $self->create_resource($req, $res);
        $res->PhysicalResourceId(FAILED_CREATION_ID) if (not defined $res->PhysicalResourceId and $res->Status eq 'FAILED');
        SQS::Worker::CloudFormationResourceException->throw(
          "No PhysicalResourceId was assigned to the response in the create_resource call"
        ) if (not defined $res->PhysicalResourceId);
      };
      if ($@) {
        $self->log->error($@);
        $res->Status('FAILED');
        $res->Reason('Creation failed due to an unhandled internal error');
        $res->PhysicalResourceId(FAILED_CREATION_ID);
      }
    } elsif ($req->RequestType eq 'Update') {
      eval {
        $self->update_resource($req, $res);
      };
      if ($@) {
        $self->log->error($@);
        $res->Status('FAILED');
        $res->Reason('Update failed due to an unhandled internal error');
      }
    } elsif ($req->RequestType eq 'Delete') {
      # Assign the PhysicalResourceId for the response, as DELETE needs this 
      # even if the resource fails or succeeds creation
      $res->PhysicalResourceId($req->PhysicalResourceId);

      # When a create fails, and cloudformation rolls back, it sends a
      # DELETE for that rolled back item
      if ($req->PhysicalResourceId eq FAILED_CREATION_ID) {
        $self->log->info("Rollback detected. Skipping delete");
        $res->Status('SUCCESS');
        $res->Reason('Rollback approved');
      } else {
        eval {
          $self->delete_resource($req, $res);
        };
        if ($@) {
          $self->log->error($@);
          $res->Status('FAILED');
          $res->Reason('Delete failed due to an unhandled internal error');
        }
      }
    } else {
      SQS::Worker::CloudFormationResourceException->throw("Unrecognized RequestType " . $req->RequestType);
    }

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

  $result->Status('SUCCESS');
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
to an SQS queue. You can setup 

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

  { "Fn::GetAtt": [ "Custom1", "Color" ]

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
