package SQS::Worker::CloudFormationResource::Request {
  use Moose::Util::TypeConstraints;
  enum 'SQS::Worker::CloudFormationResource::RequestType', [qw/Create Update Delete/];

  use Moose;

  has RequestType => (is => 'ro', isa => 'SQS::Worker::CloudFormationResource::RequestType', required => 1);
  has ResponseURL => (is => 'ro', isa => 'Str', required => 1);
  has StackId     => (is => 'ro', isa => 'Str', required => 1);
  has RequestId   => (is => 'ro', isa => 'Str', required => 1);
  has ResourceType => (is => 'ro', isa => 'Str', required => 1);
  has LogicalResourceId => (is => 'ro', isa => 'Str', required => 1);
  has PhysicalResourceId => (is => 'ro', isa => 'Str');
  has ResourceProperties => (is => 'ro', isa => 'HashRef[Any]');
  has OldResourceProperties => (is => 'ro', isa => 'HashRef[Any]');

  __PACKAGE__->meta->make_immutable;
}
1;
