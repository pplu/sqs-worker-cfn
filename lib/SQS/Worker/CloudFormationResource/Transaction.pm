package SQS::Worker::CloudFormationResource::Transaction {
  use Moose;
  has Request  => (is => 'ro', isa => 'SQS::Worker::CloudFormationResource::Request', required => 1);
  has Response => (is => 'ro', isa => 'SQS::Worker::CloudFormationResource::Response', required => 1);

  __PACKAGE__->meta->make_immutable;
}
1;
