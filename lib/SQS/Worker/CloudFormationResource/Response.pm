package SQS::Worker::CloudFormationResource::Response {
  use Moose::Util::TypeConstraints;
  enum 'SQS::Worker::CloudFormationResource::StatusType', [qw/SUCCESS FAILED/];

  use Moose;
  use JSON qw/encode_json/;

  has Status => (is => 'rw', isa => 'SQS::Worker::CloudFormationResource::StatusType');
  has Reason => (is => 'rw', isa => 'Str');
  has PhysicalResourceId => (is => 'rw', isa => 'Str');
  has StackId => (is => 'ro', isa => 'Str', required => 1);
  has RequestId => (is => 'ro', isa => 'Str', required => 1);
  has LogicalResourceId => (is => 'ro', isa => 'Str', required => 1);
  has Data => (is => 'rw', isa => 'HashRef[Any]');

  sub to_json {
    my $self = shift;
    for my $property (qw/Status/) {
      die "No $property was set up" if (not defined $self->$property);
    }
    my $hash = {};
    foreach ($self->meta->get_all_attributes) {
       my $value = $_->get_value($self);
       if(defined $value) { $hash->{$_->name} = $value; }
    }
    my $json = encode_json $hash;

    return $json;
  }

  __PACKAGE__->meta->make_immutable;
}
1;
