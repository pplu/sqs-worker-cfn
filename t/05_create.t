#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::Exception;
use SNS::Notification;
use JSON::MaybeXS qw/encode_json/;

package DummyLog {
  use Moose;
  use v5.10;
  sub info { }
  sub error { }
  sub debug { }
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

package CreationTestWorker1 {
  use Moose;
  with 'SQS::Worker::CloudFormationResource';

  has log => (is => 'ro', default => sub { DummyLog->new });

  sub create_resource {
    my ($self, $req, $res) = @_;
    # Set the PhysicalResourceId, but don't communicate success
    $res->PhysicalResourceId('resource-id1');
  };
  sub update_resource {
  };
  sub delete_resource {
  };
}

{
  my $response;

  my $w = CreationTestWorker1->new(
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
 
  diag "Create response";
  diag $response;

  like($response, qr|"Status":"FAILED"|, 'send cfn a fail due to an exception in the create_resource handler'); 
  like($response, qr|"Reason":"Creation failed due to an unhandled internal error"|, 'with an appropiate message'); 
  like($response, qr|"PhysicalResourceId":"FAILEDRESOURCECREATE"|, 'the resourceid sent to cfn is the special one that SQS::Worker::CloudFormationResource fills in');
}

package CreationTestWorker2 {
  use Moose;
  with 'SQS::Worker::CloudFormationResource';

  has log => (is => 'ro', default => sub { DummyLog->new });

  sub create_resource {
    my ($self, $req, $res) = @_;
    $res->set_success('It all went well, but I am not going to set the PhysicalResourceId');
  };
  sub update_resource {
  };
  sub delete_resource {
  };
}

{
  my $response;

  my $w = CreationTestWorker2->new(
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
 
  diag "Create response";
  diag $response;

  like($response, qr|"Status":"FAILED"|, 'send cfn a fail due to an exception in the create_resource handler'); 
  like($response, qr|"Reason":"Creation failed due to an unhandled internal error"|, 'with an appropiate message'); 
  like($response, qr|"PhysicalResourceId":"FAILEDRESOURCECREATE"|, 'the resourceid sent to cfn is the special one that SQS::Worker::CloudFormationResource fills in');
}

done_testing;
