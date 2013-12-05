
use strict;
use warnings;

use 5.008;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Business::CPI's PagSeguro driver",
  "AUTHOR" => "Andr\x{e9} Walker <andre\@andrewalker.net>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Business-CPI-Gateway-PagSeguro",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Business::CPI::Gateway::PagSeguro",
  "PREREQ_PM" => {
    "Business::CPI" => "0.910",
    "DateTime" => 0,
    "LWP::Simple" => 0,
    "Locale::Country" => 0,
    "Moo" => "1.0",
    "URI" => 0,
    "XML::LibXML" => 0
  },
  "TEST_REQUIRES" => {},
  "VERSION" => "0.903",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Business::CPI" => "0.910",
  "DateTime" => 0,
  "LWP::Simple" => 0,
  "Locale::Country" => 0,
  "Moo" => "1.0",
  "URI" => 0,
  "XML::LibXML" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



