package CustomResourceExample1 {
  use Moose;
  with 'SQS::Worker', 'SQS::Worker::SNS', 'SQS::Worker::CloudFormationResource';

  use Data::Dumper;

  sub create_resource {
    my ($self, $request, $result) = @_;
    # $request is a SQS::Worker::CloudFormationResource::Request
    # $result  is a SQS::Worker::CloudFormationResource::Response
    $self->log->error('create_resource');
    $self->log->error(Dumper($request, $result));
    die "Aborting resource creation";
  }

  sub update_resource {
    my ($self, $request, $result) = @_;
    $self->log->error('update_resource');
    $self->log->error(Dumper($request, $result));
    die "Aborting resource update";
  }

  sub delete_resource {
    my ($self, $request, $result) = @_;
    $self->log->error('delete_resource');
    $self->log->error(Dumper($request, $result));
    die "Aborting resource delete";
  }
}
1;
