package SQS::Worker::CloudFormationResourceException;
  use Moose;
  extends 'Throwable::Error';

  __PACKAGE__->meta->make_immutable;
1;
