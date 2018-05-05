#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::Exception;
use SNS::Notification;
use JSON::MaybeXS;

package DummyLog {
  use Moose;
  sub info {}
  sub error {}
  sub debug {}
}

package ExceptionTestWorker {
  use Moose;
  with 'SQS::Worker::CloudFormationResource';

  has log => (is => 'ro', default => sub { DummyLog->new });

  sub create_resource {
    my ($self, $req, $res) = @_;
    die "Called create_resource";
  };
  sub update_resource {
    my ($self, $req, $res) = @_;
    die "Called update_resource";
  };
  sub delete_resource {
    my ($self, $req, $res) = @_;
    die "Called delete_resource";
  };
}

sub make_sns_notification {
  my %message_info = @_;
  my $sns = SNS::Notification->new(
    Message => encode_json({ %message_info }),
    Timestamp => 'fake_ts',
    TopicArn => 'fake_arn',
    Type => 'fake_type',
    UnsubscribeURL => 'http://fake_url',
    Subject => 'fake_subject',
    MessageId => 'fake_message_id',
    Signature => 'fake_signature',
    SignatureVersion => 1,
    SigningCertURL => 'http://fake_url', 
  );
  return $sns;
}

package FakeHTTP {
  use Moose;

  has code => (is => 'ro', isa => 'CodeRef', required => 1);

  sub put {
    my ($self, $url, $headers, $body) = @_;
    $self->code->($body);
  }
}

{
  my $response;

  my $w = ExceptionTestWorker->new(
    http_client => FakeHTTP->new(
      code => sub { $response = $_[0] }      
    )
  );

  $w->process_message(make_sns_notification(
    RequestType => 'Create',
    ResponseURL => 'http://localhost',
    StackId => 'fake_arn',
    RequestId => 'fake_request_id',
    ResourceType => 'Custom::MyResource',
    LogicalResourceId => 'MyResource',
    ResourceProperties => {
      Prop1 => 'Prop1Value',
    }
  ));
 
  like($response, qr|"Status":"FAILED"|, 'send cfn a fail due to an exception in the create_resource handler'); 
  like($response, qr|"Reason":"Creation failed due to an unhandled internal error"|, 'with an appropiate message'); 
  like($response, qr|"PhysicalResourceId":"FAILEDRESOURCECREATE"|, 'the resourceid sent to cfn is the special one that SQS::Worker::CloudFormationResource fills in');

  $response = undef;
  $w->process_message(make_sns_notification(
    RequestType => 'Update',
    ResponseURL => 'http://localhost',
    StackId => 'fake_arn',
    RequestId => 'fake_request_id',
    ResourceType => 'Custom::MyResource',
    LogicalResourceId => 'MyResource',
    PhysicalResourceId => 'generated-id-1',
    ResourceProperties => {
      Prop1 => 'Prop1Value',
    }
  ));

  like($response, qr|"Status":"FAILED"|, 'send cfn a fail due to an exception in the update_resource handler');
  like($response, qr|"Reason":"Update failed due to an unhandled internal error"|, 'with an appropiate message'); 

  $response = undef;
  $w->process_message(make_sns_notification(
    RequestType => 'Delete',
    ResponseURL => 'http://localhost',
    StackId => 'fake_arn',
    RequestId => 'fake_request_id',
    ResourceType => 'Custom::MyResource',
    LogicalResourceId => 'MyResource',
    PhysicalResourceId => 'generated-id-1',
    ResourceProperties => {
      Prop1 => 'Prop1Value',
    }
  ));

  like($response, qr|"Status":"FAILED"|, 'send cfn a fail due to an exception in the delete_resource handler');
  like($response, qr|"Reason":"Delete failed due to an unhandled internal error"|);
}

done_testing;
