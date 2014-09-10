#! /usr/bin/env perl

use strict;
use warnings;
use Test::Script::Run;
use Test::More 'tests' => 31;     # Main test module; run this many subtests

use Bio::SeqWare::Uploads::CgHub::Bam;
my $APP = 'upload-cghub-bam';
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 status-local);

# Application shebang line test. This seems excessive but added because I got
# this wrong and the app wouldn't actually run, although all tests passed.
{
    my $message = "Correct shebang line";
    my $perlExec = 'blib/script/upload-cghub-bam';
    if (! -f $perlExec) {
        diag("$perlExec does not exist");
    }
    open my $fh, '<', $perlExec or die "$perlExec: $!";
    chomp(my $line = <$fh>);
    close $fh or die "$perlExec: $!";
    {
        like( $line, qr/^#!\s?\/usr\/bin\/env perl/, $message);
    }
}

# Application runs (smoke test)
{
   run_ok( $APP, [@DEF_CLI], "Minimal run succeeds");
}

# Testing exit run with --version option
{
    my @appArgs = qw(--version);
    my $version = $Bio::SeqWare::Uploads::CgHub::Bam::VERSION;
    my @appOutLines = ("upload-cghub-bam v$version",);
    {
        run_output_matches( $APP, \@appArgs, \@appOutLines, []);
    }
}

# Testing output help message when using bad option.
{
    my @appArgs = qw(--noSuchOptError status-local);
    my $appOut;
    my $appErr;
    run_script( $APP, \@appArgs, \$appOut, \$appErr );
    {
        is( $appOut, "", "Bad option not output to StdOut");
        like( $appErr, qr/.*Unknown option: nosuchopterror.*/s, "Bad Option message on StdErr");
        like( $appErr, qr/.*upload-cghub-bam \[options\].*/s, "Synopsis message provided on error");
        like( $appErr, qr/.*--version.*/s, "--version in synopsis");
        like( $appErr, qr/.*--help.*/s, "--help in synopsis");
        like( $appErr, qr/.*--verbose.*/s, "--verbose in synopsis");
        like( $appErr, qr/.*--debug.*/s, "--debug in synopsis");
        like( $appErr, qr/.*--config.*/s, "--config in synopsis");
        like( $appErr, qr/.*--log.*/s, "--log in synopsis");
        like( $appErr, qr/.*--dbUser.*/s, "--dbUser in synopsis");
        like( $appErr, qr/.*--dbHost.*/s, "--dbHost in synopsis");
        like( $appErr, qr/.*--dbSchema.*/s, "--dbSchema in synopsis");
        like( $appErr, qr/.*--dbPassword.*/s, "--dbPassword in synopsis");
        unlike( $appErr, qr/Options:|DESCRIPTION/s, "Only synopsis, not everything else");
    }
}

# Testing output help message when asking for help.
{
    my @appArgs = qw(--help);
    my $appOut;
    my $appErr;
    run_script( $APP, \@appArgs, \$appOut, \$appErr );
    {
        SKIP: {
            skip "Pod::Perldoc thinks groff is too old.", 1, if ($appErr =~ /You have an old groff/s );
            is( $appErr, "", "--help not output to StdErr");
        }
        like( $appOut, qr/upload-cghub-bam \[options\]/s, "Synopsis message provided for --help");
        like( $appOut, qr/--version/s, "--version with --help");
        like( $appOut, qr/--help/s,    "--help with --help"   );
        like( $appOut, qr/--verbose/s, "--verbose with --help");
        like( $appOut, qr/--debug/s,   "--debug with --help"  );
        like( $appOut, qr/--config/s,  "--config with --help" );
        like( $appOut, qr/--log/s,     "--config with --log"  );
        like( $appOut, qr/--dbUser/s,     "--config with --dbUser"    );
        like( $appOut, qr/--dbHost/s,     "--config with --dbHost"    );
        like( $appOut, qr/--dbSchema/s,   "--config with --dbSchema"  );
        like( $appOut, qr/--dbPassword/s, "--config with --dbPassword");
        like( $appOut, qr/Options:/s, "More details");
        unlike( $appOut, qr/DESCRIPTION/s, "Not everything.");
    }
}