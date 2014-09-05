#! /usr/bin/env perl

use Data::Dumper;                # Simple data structure printing
use Scalar::Util qw( blessed );  # Get class of objects

use Test::Output;                # Tests what appears on stdout.
use Test::More 'tests' => 8;     # Main test module; run this many subtests
use Test::Exception;             # Test failures

use File::HomeDir qw(home);  # Finding the home directory is hard.
use File::Spec;              # Generic file handling.

use Bio::SeqWare::Config;    # To get default config file name

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my $TEST_CFG = File::Spec->catfile( "t", "Data", "test with space.config" );

# Run these tests
subtest( 'new()'      => \&testNew );
subtest( 'run()'      => \&testRun );
subtest( 'parseCli()'    => \&testParseCli    );
subtest( 'loadOptions()' => \&testLoadOptions );
subtest( 'fixupTildePath()' => \&testFixupTildePath );
subtest( 'getConfigOptions()' => \&testGetConfigOptions );
subtest( 'say(),sayDebug(),SayVerbose()' => \&testSayAndSayDebugAndSayVerbose );
subtest( 'makeUuid()' => \&testMakeUuid );

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
    plan( tests => 8 );

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
            ok( $obj->{'verbose'}, "verbose and debug sets verbose");
            ok( $obj->{'debug'}, "verbose and debug sets debug");
        }
    }

    # _argvAR
    {
        @ARGV = qw(--verbose --debug);
        my $obj = $CLASS->new();
        # loadOptions called to do this...
        is_deeply($obj->{'_argvAR'}, ['--verbose', '--debug'], "ARGV was captured.");
    }
    # _optHR
    {
        @ARGV = qw(--debug);
        my $obj = $CLASS->new();
        # loadOptions called to do this...
        ok($obj->{'_optHR'}->{'debug'}, "optHR was captured.");
    }

}

sub testParseCli {
    plan( tests => 6 );
    my $obj = $CLASS->new();

    # --verbose
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

    # --debug
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

    # --config
    {
         my $message = "--config default is set";
         @ARGV = qw();
         my $opt = $obj->parseCli();
         is( $opt->{'config'}, Bio::SeqWare::Config->getDefaultFile(), $message );
    }
    {
         my $message = "--config flag can be set";
         @ARGV = qw(--config some/new.cfg);
         my $opt = $obj->parseCli();
         is( $opt->{'config'}, "some/new.cfg", $message );
    }

}

sub testSayAndSayDebugAndSayVerbose {
    plan( tests => 18 );

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

    # $object parameter is string.
    {
        @ARGV = qw(--debug);
        my $obj = $CLASS->new();
        my $text = 'Say with scalar object.';
        my $object = 'The second object';
        my $expect = "$text\n$object";
        {
            stdout_is { $obj->sayDebug(   $text, $object ); } $expect, "--Scalar object and sayDebug";
            stdout_is { $obj->sayVerbose( $text, $object ); } $expect, "--Scalar object and sayVerbose";
            stdout_is { $obj->say(        $text, $object ); } $expect, "--Scalar object and say";
        }
    }

    # $object parameter is hashRef.
    {
        @ARGV = qw(--debug);
        my $obj = $CLASS->new();
        my $text = 'Say with hashRef object.';
        my $object = {'key'=>'value'};
        my $objectString = Dumper($object);
        my $expect = "$text\n$objectString";
        {
            stdout_is { $obj->sayDebug(   $text, $object ); } $expect, "--hashRef object and sayDebug";
            stdout_is { $obj->sayVerbose( $text, $object ); } $expect, "--hashRef object and sayVerbose";
            stdout_is { $obj->say(        $text, $object ); } $expect, "--hashRef object and say";
        }
    }

    # $object parameter is arrayRef.
    {
        @ARGV = qw(--debug);
        my $obj = $CLASS->new();
        my $text = 'Say with arrayRef object.';
        my $object = ['key', 'value'];
        my $objectString = Dumper($object);
        my $expect = "$text\n$objectString";
        {
            stdout_is { $obj->sayDebug(   $text, $object ); } $expect, "--arrayRef object and sayDebug";
            stdout_is { $obj->sayVerbose( $text, $object ); } $expect, "--arrayRef object and sayVerbose";
            stdout_is { $obj->say(        $text, $object ); } $expect, "--arrayRef object and say";
        }
    }

}

sub testFixupTildePath {
    plan( tests => 5 );

    my $obj = $CLASS->new();
    my $home = home();
    is( $obj->fixupTildePath( "a/path/" ), "a/path/", "path without tilde" );
    is( $obj->fixupTildePath( "~" ), home(), "path is just a tilde" );
    is( $obj->fixupTildePath( "~/a/path/" ),  home() . "/a/path/", "path with tilde" );
    is( $obj->fixupTildePath( "" ), "", "path is empty string" );
    is( $obj->fixupTildePath( undef ), undef, "path is undefined" );
}

sub testGetConfigOptions {
    plan( tests => 4);

    # Testing with default config file
    {
        @ARGV = qw();
        my $obj = $CLASS->new();

        my $defaultConfig = Bio::SeqWare::Config->getDefaultFile();
        SKIP: {
            skip "No default config file", 1, unless ( -f $defaultConfig );
            {
                my $message = "Config options available";
                my $opt = $obj->getConfigOptions( $defaultConfig );
                my $got = $opt->{'dbUser'};
                my $want = "seqware";
                is( $got, $want, $message);
            }
        }
        {
            my $message = "Dies with bad filename";
            my $badFileName = $obj->makeUuid() . ".notAnExistingFile";
            my $expectError = qr/^Can't find config file: "$badFileName"\./;
            throws_ok( sub { $obj->getConfigOptions($badFileName) }, $expectError, $message);
        }
        {
            my $message = "Dies with no filename";
            my $badFileName = undef;
            my $expectError = qr/^Can't find config file: <undef>\./;
            throws_ok( sub { $obj->getConfigOptions($badFileName) }, $expectError, $message);
        }
    }

    # Testing with test config file
    {
        @ARGV = ('--config', "$TEST_CFG");
        my $obj = $CLASS->new();
        {
            my $message = "Test config options available";
            my $opt = $obj->getConfigOptions( $obj->{'_optHR'}->{'config'} );
            my $got = $opt->{'dbPassword'};
            my $want = "seqware";
            is( $got, $want, $message);
        }
    }
}

sub testMakeUuid {
    plan( tests => 3);

    @ARGV = qw();
    my $obj = $CLASS->new();

    my $uuid = $obj->makeUuid();
    my $uuid2 = $obj->makeUuid();
    like( $uuid, qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/, "uuid generated as string");
    like( $uuid2, qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/, "another uuid generated as string");
    isnt( $uuid, $uuid2, "two successive uuids are not the same");
}