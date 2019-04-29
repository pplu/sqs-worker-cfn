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

package RoutingTestWorker {
  use Moose;
  with 'SQS::Worker::CloudFormationResource';

  has log => (is => 'ro', default => sub { DummyLog->new });

  use Test::More;

  sub create_resource {
    my ($self, $req, $res) = @_;
    cmp_ok($req->ResourceProperties->{ Prop1 }, 'eq', 'Prop1Value');
    $res->set_success('called create_resource');
    $res->Data({ Result1 => 'Result1Value' });
    $res->PhysicalResourceId('resource-id1');
  };
  sub update_resource {
    my ($self, $req, $res) = @_;
    cmp_ok($req->OldResourceProperties->{ Prop1 }, 'eq', 'Prop1Value');
    cmp_ok($req->ResourceProperties->{ Prop1 }, 'eq', 'NewProp1Value');
    $res->Data({ Result1 => 'Result1ValueUpdate' });
    $res->set_success('called update_resource');
  };
  sub delete_resource {
    my ($self, $req, $res) = @_;
    $res->set_success('called delete_resource');
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

  my $w = RoutingTestWorker->new(
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

  like($response, qr|"Status":"SUCCESS"|, 'send cfn a success'); 
  like($response, qr|"Reason":"called create_resource"|, 'with the message from the create_resource function'); 
  like($response, qr|"PhysicalResourceId":"resource-id1"|, 'sent the correct resource id');
  like($response, qr|"Data":\{"Result1":"Result1Value"}|, 'got the data back');

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
      Prop1 => 'NewProp1Value',
    },
    OldResourceProperties => {
      Prop1 => 'Prop1Value',
    }
  ));

  diag "Update response";
  diag $response;

  like($response, qr|"Status":"SUCCESS"|, 'send cfn a success');
  like($response, qr|"Reason":"called update_resource"|, 'with the message from the update_resource function'); 
  like($response, qr|"Data":{"Result1":"Result1ValueUpdate"}|, 'got the data back');

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

  diag "Delete response";
  diag $response;

  like($response, qr|"Status":"SUCCESS"|, 'send cfn a success');
  like($response, qr|"Reason":"called delete_resource"|, 'with the message from the delete_resource function');
}

done_testing;
