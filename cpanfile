requires 'SQS::Worker';
requires 'Furl';
requires 'IO::Socket::SSL';
requires 'JSON::MaybeXS';
requires 'Throwable::Error';

on 'test' => sub {
  requires 'Test::More';
  requires 'Test::Exception';
};

