#! /usr/bin/env perl

use Scalar::Util qw( blessed );  # Get class of objects

use Test::Output;                # Tests what appears on stdout.
use Test::More 'tests' => 5;     # Main test module; run this many subtests

use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

# Run these tests
subtest( 'new()'      => \&testNew );
subtest( 'run()'      => \&testRun );
subtest( 'parseCli()'    => \&testParseCli    );
subtest( 'loadOptions()' => \&testLoadOptions );
subtest( 'say(),sayDebug(),SayVerbose()' => \&testSayAndSayDebugAndSayVerbose );

sub testNew {
    plan( tests => 1 );

    my $obj = $CLASS->new();
    {
        my $message = "Returns object of correct type";
        my $want = $CLASS;
        my $got = blessed( $obj );
        is( $got, $want, $message );
    }
}

sub testRun {
    plan( tests => 1 );

    my $obj = $CLASS->new();
    {
        my $message = "run succeeds";
        my $want = 1;
        my $got = $obj->run();
        is( $got, $want, $message );
    }
}

sub testLoadOptions {
    plan( tests => 6 );

    # --verbose only
    {
        my $obj = $CLASS->new();
        my $optHR = {'verbose' => 1};
        $obj->loadOptions($optHR);
        {
            ok( $obj->{'verbose'}, "verbose only sets verbose");
            ok( ! $obj->{'debug'}, "verbose only does not set debug");
        }
    }
    # --debug only
    {
        my $obj = $CLASS->new();
        my $optHR = {'debug' => 1};
        $obj->loadOptions($optHR);
        {
            ok( $obj->{'debug'}, "debug only sets debug");
            ok( $obj->{'verbose'}, "debug only sets verbose");
        }
    }
    # --verbose && --debug
    {
        my $obj = $CLASS->new();
        my $optHR = {'verbose' => 1, 'debug' => 1};
        $obj->loadOptions($optHR);
        {
            ok( $obj->{'verbose'}, "verbose and debg sets verbose");
            ok( $obj->{'debug'}, "verbose and debg sets debug");
        }
    }

}

sub testParseCli {
    plan( tests => 4 );
    my $obj = $CLASS->new();
    {
         my $message = "--verbose flag default is unset";
         @ARGV = qw();
         my $opt = $obj->parseCli();
         ok( ! $opt->{'verbose'}, $message );
    }
    {
         my $message = "--verbose flag can be set";
         @ARGV = qw(--verbose);
         my $opt = $obj->parseCli();
         ok( $opt->{'verbose'}, $message );
    }
    {
         my $message = "--debug flag default is unset";
         @ARGV = qw();
         my $opt = $obj->parseCli();
         ok( ! $opt->{'debug'}, $message );
    }
    {
         my $message = "--debug flag can be set";
         @ARGV = qw(--debug);
         my $opt = $obj->parseCli();
         ok( $opt->{'debug'}, $message );
    }
}

sub testSayAndSayDebugAndSayVerbose {
    plan( tests => 9 );

    # --debug set
    {
        @ARGV = qw(--debug);
        my $obj = $CLASS->new();
        my $text = 'Say with debug on';
        my $expectRE = qr/^$text$/;
        {
            stdout_like { $obj->sayDebug(   $text ); } $expectRE, "--debug and sayDebug";
            stdout_like { $obj->sayVerbose( $text ); } $expectRE, "--debug and sayVerbose";
            stdout_like { $obj->say(        $text ); } $expectRE, "--debug and say";
        }
    }

    # --verbose set
    {
        @ARGV = qw(--verbose);
        my $obj = $CLASS->new();
        my $text = 'Say with verbose on';
        my $expectRE = qr/^$text$/;
        {
            stdout_unlike { $obj->sayDebug(   $text ); } $expectRE, "--verbose and sayDebug";
            stdout_like   { $obj->sayVerbose( $text ); } $expectRE, "--verbose and sayVerbose";
            stdout_like   { $obj->say(        $text ); } $expectRE, "--verbose and say";
        }
    }

    # --no flag set
    {
        @ARGV = qw();
        my $obj = $CLASS->new();
        my $text = 'Say with no flag';
        my $expectRE = qr/^$text$/;
        {
            stdout_unlike { $obj->sayDebug(   $text ); } $expectRE, "no flag and sayDebug";
            stdout_unlike { $obj->sayVerbose( $text ); } $expectRE, "no flag and sayVerbose";
            stdout_like   { $obj->say(        $text ); } $expectRE, "no flag and say";
        }
    }
}