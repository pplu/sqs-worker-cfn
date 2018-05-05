requires 'SQS::Worker';
requires 'Furl';
requires 'IO::Socket::SSL';
requires 'JSON::MaybeXS';
requires 'Throwable::Error';

on 'test' => sub {
  requires 'Test::More';
  requires 'Test::Exception';
}

on 'develop' => sub {
  requires 'Dist::Zilla';
  requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile';
  requires 'Dist::Zilla::Plugin::VersionFromMainModule';
  requires 'Dist::Zilla::Plugin::Git::GatherDir';
  requires 'Dist::Zilla::Plugin::RunExtraTests';
  requires 'Dist::Zilla::PluginBundle::Git';
};
