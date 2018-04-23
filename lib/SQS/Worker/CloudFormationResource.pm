package SQS::Worker::CloudFormationResource {
  use Moose::Role;

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

    die "SQS::Worker::CloudFormationResource only knows how to process SNS::Notification objects" if (not $sns->isa('SNS::Notification'));
 
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
      # When a create fails, and cloudformation rolls back, it sends a
      # DELETE for that rolled back item
      if ($req->PhysicalResourceId eq FAILED_CREATION_ID) {
        $self->log->info("Rollback detected. Skipping delete");
        $res->Status('SUCCESS');
        $res->Reason('Rollback approved');
        $res->PhysicalResourceId(FAILED_CREATION_ID);
      } else {
        eval {
          $self->delete_resource($req, $res);
        };
        if ($@) {
          $self->log->error($@);
          $res->Status('FAILED');
          $res->Reason('Delete failed due to an unhandled internal error');
          $res->PhysicalResourceId(FAILED_CREATION_ID);
        }
      }
    } else {
      die "Unrecognized RequestType " . $req->RequestType;
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
