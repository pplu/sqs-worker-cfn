#!/usr/bin/env perl

use Test::More;
use Test::Exception;

package DummyLog {
  use Moose;
  sub info {}
  sub error {}
  sub debug {}
}

package TestWorker {
  use Moose;
  with 'SQS::Worker', 'SQS::Worker::CloudFormationResource';

  sub create_resource {};
  sub update_resource {};
  sub delete_resource {};
}

{
  my $w = TestWorker->new(
    queue_url => 'fake',
    region => 'fake',
    log => DummyLog->new,
  );

  dies_ok(sub {
    $w->process_message('{"a":"random_message"}');
  }, qr/SQS::Worker::CloudFormationResource only knows how to process SNS::Notification objects. Does your worker also consume SQS::Worker::SNS/);
}

done_testing;
