readme:
	cpanm -l dzil-local -n Pod::Markdown
	perl -I dzil-local/lib/perl5/ dzil-local/bin/pod2markdown lib/SQS/Worker/CloudFormationResource.pm > README.md

dist: readme
	cpanm -n -l dzil-local Dist::Zilla
	PATH=$(PATH):dzil-local/bin PERL5LIB=dzil-local/lib/perl5 dzil authordeps --missing | cpanm -n -l dzil-local/
	PATH=$(PATH):dzil-local/bin PERL5LIB=dzil-local/lib/perl5 dzil build

test:
	PERL5LIB=local/lib/perl5 prove -I lib -v t/


