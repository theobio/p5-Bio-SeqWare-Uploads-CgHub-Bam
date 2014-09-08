#! /usr/bin/env perl

use Data::Dumper;                # Simple data structure printing
use Scalar::Util qw( blessed );  # Get class of objects

use Test::Output;                # Tests what appears on stdout.
use Test::More 'tests' => 17;    # Main test module; run this many subtests
use Test::Exception;             # Test failures

use Test::MockModule;            # Fake subroutine returns from other modules.
use DBD::Mock;                   # Fake database results.
use Test::MockObject::Extends;   # Fake subroutines from this module.

use File::HomeDir qw(home);  # Finding the home directory is hard.
use File::Spec;              # Generic file handling.

use Bio::SeqWare::Config;          # To get default config file name
use Bio::SeqWare::Db::Connection;  # Database handle generation, for mocking

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my $TEST_CFG = File::Spec->catfile( "t", "Data", "test with space.config" );
my $SAMPLE_FILE_BAM = File::Spec->catfile( "t", "Data", "samplesToUpload.txt" );
my $SAMPLE_FILE = File::Spec->catfile( "t", "Data", "sampleList.txt" );
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy status-local);

# Run these tests
subtest( 'new()'      => \&testNew );
subtest( 'run()'      => \&testRun );
subtest( 'parseCli()'    => \&testParseCli    );
subtest( 'loadOptions()'   => \&testLoadOptions );

subtest( 'loadArguments()' => \&testLoadArguments );
subtest( 'fixupTildePath()' => \&testFixupTildePath );
subtest( 'getConfigOptions()' => \&testGetConfigOptions );
subtest( 'say(),sayDebug(),SayVerbose()' => \&testSayAndSayDebugAndSayVerbose );
subtest( 'getUuid()'     => \&testGetUuid    );
subtest( 'getTimestamp()' => \&testGetTimestamp);
subtest( 'getLogPrefix()' => \&testGetLogPrefix);
subtest( 'logifyMessage()' => \&testLogifyMessage);
subtest( 'parseSampleFile()' => \&testParseSampleFile);
subtest( 'getDbh()'  => \&testGetDbh);
subtest( 'DESTROY()' => \&testDESTROY );
subtest( 'setUploadStatus()' => \&testSetUploadStatus );
subtest( 'setUDone()' => \&testSetDone );

sub testNew {
    plan( tests => 2 );

    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    {
        my $message = "Returns object of correct type";
        my $want = $CLASS;
        my $got = blessed( $obj );
        is( $got, $want, $message );
    }
    {
        my $message = "Has UUID";
        my $got = $obj->{'id'};
        my $expectRE =  qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/;
        like( $got, $expectRE, $message );
    }
}

sub testDESTROY {
    plan( tests => 3 );
    {
        my $message = "DESTROY dbh closed";
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        $obj->{'dbh'}->disconnect();
        $obj->{'dbh'}->{mock_can_connect} = 0;
        undef $obj;  # Invokes DESTROY.
        is( $obj, undef, $message);
    }
    {
        my $message = "DESTROY dbh open";
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        undef $obj;  # Invokes DESTROY.
        is( $obj, undef, $message);
    }
    {
        my $message = "DESTROY dbh open wth transaction";
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        $obj->{'dbh'}->begin_work();
        undef $obj;  # Invokes DESTROY.
        is( $obj, undef, $message);
    }
}

sub testGetDbh {
    plan( tests => 4 );

    {
        my $message = "Returns cahced value if any";
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        my $dbh = $obj->getDbh();
        my $got = blessed $dbh;
        my $want = "DBI::db";
        is( $got, $want, $message );
    }

    {
        my $message = "Error if failes to get connection";
        my $obj = makeBam();
        my $module = new Test::MockModule( 'Bio::SeqWare::Db::Connection' );
        $module->mock( 'getConnection', sub { return undef } );
        my $errorRE = qr/^DbConnectException: Failed to connect to the database\./;
        throws_ok( sub { $obj->getDbh(); }, $errorRE, $message )
    }

    {
        my $obj = makeBam();
        my $module = new Test::MockModule( 'Bio::SeqWare::Db::Connection' );
        $module->mock( 'getConnection', sub { return makeMockDbh() } );
        my $dbh = $obj->getDbh();
        {
             my $message = "Returns new connection when creating one";
             my $got = blessed $dbh;
             my $want = "DBI::db";
             is( $got, $want, $message );
        }
        {
             my $message = "Caches new connection when creating one";
             my $dbh = $obj->{'dbh'};
             my $got = blessed $dbh;
             my $want = "DBI::db";
             is( $got, $want, $message );
        }
    }
}

sub testSetUploadStatus {
    plan( tests => 3 );

    # valid run.
    my $newStatus = "dummy_done";
    my $upload_id = 21;
    {
        my @dbEvent = ({
            'statement'   => qr/UPDATE upload SET status = .*/msi,
            'bound_params' => [ $newStatus, $upload_id ],
            'results'  => [ [ 'rows' ], [] ],
        });
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setUploadStatus', @dbEvent );
        {
            my $message = "setUploadStatus with good data works.";
            my $got = $obj->setUploadStatus( $upload_id, $newStatus );
            my $want = 1;
            is( $got, $want, $message );
        }
    }

    # Bad returned results.
    {
        my @dbEvent = ({
            'statement'   => qr/UPDATE upload SET status = .*/msi,
            'bound_params' => [ $newStatus, $upload_id ],
            'results'  => [ [ 'rows' ], ],
        });
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'badSetUploadStatus', @dbEvent );
        {
            my $message = "setUploadStatus fails if db returns unexpected results.";
            my $error1RES = 'DbStatusUpdateException: Failed to change upload record ' . $upload_id. ' to ' . $newStatus. '\.';
            my $error2RES = 'Cleanup likely needed\. Error was:';
            my $error3RES = 'Updated 0 update records, expected 1\.';
            my $errorRE = qr/$error1RES\n$error2RES\n$error3RES/m;
            throws_ok( sub { $obj->setUploadStatus( $upload_id, $newStatus ); }, $errorRE, $message);
        }
    }

    # DB error.
    {
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql => "UPDATE upload SET status = ? WHERE upload_id = ?",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Ooops.' ],
        };
        {
            my $message = "setUploadStatus fails if db throws error.";
            my $error1RES = 'DbStatusUpdateException: Failed to change upload record ' . $upload_id. ' to ' . $newStatus. '\.';
            my $error2RES = 'Cleanup likely needed\. Error was:';
            my $error3RES = 'Ooops\.';
            my $errorRE = qr/$error1RES\n$error2RES\n.*$error3RES/m;
            throws_ok( sub { $obj->setUploadStatus( $upload_id, $newStatus ); }, $errorRE, $message);
        }
    }
}

sub testSetDone {
    plan( tests => 1 );
    {
        my $obj = makeBam();
        $obj->{'dbh'} = makeMockDbh();
        $obj = Test::MockObject::Extends->new( $obj );
        $obj->mock( 'setUploadStatus', sub { shift; return (shift,shift,shift); } );
        {
            my $message = "Set done calls setUploadStatus correctly.";
            my @want = (21, "dummy-status_done", undef);
            my @got = $obj->setDone( {'upload_id' => 21}, "dummy-status" );
            is_deeply( \@got, \@
            want, $message);
        }
    }

}

sub testRun {
    plan( tests => 1 );

    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    {
        my $message = "run succeeds";
        my $want = 1;
        my $got = $obj->run();
        is( $got, $want, $message );
    }
}

sub testParseSampleFile {
    plan( tests => 17
     );

    # Sample with bam file and headers
    {
        @ARGV = (@DEF_CLI, "$SAMPLE_FILE_BAM");
        my $obj = $CLASS->new();
        my $sampleRecDAT = $obj->parseSampleFile();
        my $wantDAT = [
            { sample => 'TCGA1', flowcell => 'UNC1', lane => 6, barcode => '', bamFile => '' },
            { sample => 'TCGA2', flowcell => 'UNC2', lane => 7, barcode => 'ATTCGG', bamFile => '' },
            { sample => 'TCGA3', flowcell => 'UNC3', lane => 8, barcode => 'ATTCGG', bamFile => '/not/really' },
            { sample => 'TCGA4', flowcell => 'UNC4', lane => 1, barcode => '', bamFile => '/old/fake' },
        ];
        {
            my $message = "Sample count correct";
            my $got = scalar @$sampleRecDAT;
            my $want = scalar @$wantDAT;
            is( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 1 (no barcode)";
            my $got = $sampleRecDAT->[0];
            my $want = $wantDAT->[0];
            is_deeply( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 2 ( with barcode)";
            my $got = $sampleRecDAT->[1];
            my $want = $wantDAT->[1];
            is_deeply( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 3 (barcode + bamFile)";
            my $got = $sampleRecDAT->[2];
            my $want = $wantDAT->[2];
            is_deeply( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 4 (no barcode + bamFile)";
            my $got = $sampleRecDAT->[3];
            my $want = $wantDAT->[3];
            is_deeply( $got, $want, $message );
        }
    }

    # Samples no header, no extra info
    {
        @ARGV = (@DEF_CLI, "$SAMPLE_FILE");
        my $obj = $CLASS->new();
        my $sampleRecDAT = $obj->parseSampleFile();
        my $wantDAT = [
            { sample => 'TCGA1', flowcell => 'UNC1', lane => 6, barcode => '' },
            { sample => 'TCGA2', flowcell => 'UNC2', lane => 7, barcode => 'ATTCGG' },
            { sample => 'TCGA3', flowcell => 'UNC3', lane => 8, barcode => 'ATTCGG' },
            { sample => 'TCGA4', flowcell => 'UNC4', lane => 1, barcode => '' },
        ];
        {
            my $message = "Sample count correct";
            my $got = scalar @$sampleRecDAT;
            my $want = scalar @$wantDAT;
            is( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 1 (no barcode)";
            my $got = $sampleRecDAT->[0];
            my $want = $wantDAT->[0];
            is_deeply( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 2 ( with barcode)";
            my $got = $sampleRecDAT->[1];
            my $want = $wantDAT->[1];
            is_deeply( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 3 (barcode )";
            my $got = $sampleRecDAT->[2];
            my $want = $wantDAT->[2];
            is_deeply( $got, $want, $message );
        }
        {
            my $message = "Record content ok sample 4 (no barcode)";
            my $got = $sampleRecDAT->[3];
            my $want = $wantDAT->[3];
            is_deeply( $got, $want, $message );
        }
    }

    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        my $noSuchFile = $CLASS->getUuid();
        $obj->{'sampleFile'} = $noSuchFile;
        {
            my $message = "Exception if can't open file.";
            my $errorRE = qr/^Can't open sample file for reading: "$noSuchFile"\./;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
    {
        my $badSampleFile = File::Spec->catfile( "t", "Data", "badShortHeaderLine.txt" );
        @ARGV = (@DEF_CLI, $badSampleFile);
        my $obj = $CLASS->new();
        {
            my $message = "Exception if fewer heading fields than data fields.";
            my $errorRE = qr/^More data than headers: line 3 in sample file "$badSampleFile"\. Line was:\n"TCGA1\tUNC1\t6\t\t"\n/m;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
    {
        my $badSampleFile = File::Spec->catfile( "t", "Data", "badShortDataLine.txt" );
        @ARGV = (@DEF_CLI, $badSampleFile);
        my $obj = $CLASS->new();
        {
            my $message = "Exception if fewer data fields than heading fields.";
            my $errorRE = qr/^Missing data from line 3 in file "$badSampleFile"\. Line was:\n"TCGA1\tUNC1\t6"\n/;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
    {
        my $badSampleFile = File::Spec->catfile( "t", "Data", "badIncorrectHeaderLine.txt" );
        @ARGV = (@DEF_CLI, $badSampleFile);
        my $obj = $CLASS->new();
        {
            my $message = "Exception if heading line malformed.";
            my $errorRE = qr/^Looks like sample file has a bad header line: "$badSampleFile"\./;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
    {
        my $badSampleFile = File::Spec->catfile( "t", "Data", "badEmptyHeaderField.txt" );
        @ARGV = (@DEF_CLI, $badSampleFile);
        my $obj = $CLASS->new();
        {
            my $message = "Exception if heading field is blank.";
            my $errorRE = qr/^Sample file header can not have empty fields: "$badSampleFile"\./;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
    {
        my $badSampleFile = File::Spec->catfile( "t", "Data", "badDuplicatedHeaderField.txt" );
        @ARGV = (@DEF_CLI, $badSampleFile);
        my $obj = $CLASS->new();
        {
            my $message = "Exception if heading field is duplicated.";
            my $errorRE = qr/^Duplicate headings not allowed: "barcode" in sample file "$badSampleFile"\./;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
    {
        my $badSampleFile = File::Spec->catfile( "t", "Data", "badNoHeaderWithExtraData.txt" );
        @ARGV = (@DEF_CLI, $badSampleFile);
        my $obj = $CLASS->new();
        {
            my $message = "Exception if no header and other than four data columns.";
            my $errorRE = qr/^More data than headers: line 2 in sample file "$badSampleFile"\. Line was:\n"TCGA1\tUNC1\t6\t\t"\n/m;
            throws_ok( sub { $obj->parseSampleFile(); }, $errorRE, $message );
        }
    }
}

sub testLoadOptions {
    plan( tests => 15 );

    my %dbOpt = (
        'dbUser' => 'dummy', 'dbPassword' => 'dummy',
        'dbHost' => 'host', 'dbSchema' => 'dummy',
    );

    # --verbose only
    {
        @ARGV = ('--verbose', @DEF_CLI);
        my $obj = $CLASS->new();
        my $optHR = {'verbose' => 1, %dbOpt};
        $obj->loadOptions($optHR);
        {
            ok( $obj->{'verbose'}, "verbose sets verbose");
            ok( ! $obj->{'debug'}, "verbose does not set debug");
        }
    }
    # --debug only
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        my $optHR = {'debug' => 1, %dbOpt};
        $obj->loadOptions($optHR);
        {
            ok( $obj->{'debug'}, "debug sets debug");
            ok( $obj->{'verbose'}, "debug sets verbose");
        }
    }
    # --verbose && --debug
    {
        @ARGV = ('--debug', '--verbose', @DEF_CLI);
        my $obj = $CLASS->new();
        my $optHR = {'verbose' => 1, 'debug' => 1, %dbOpt};
        $obj->loadOptions($optHR);
        {
            ok( $obj->{'verbose'}, "verbose and debug sets verbose");
            ok( $obj->{'debug'}, "verbose and debug sets debug");
        }
    }

    # --log
    {
        @ARGV = ('--log', @DEF_CLI);
        my $obj = $CLASS->new();
        my $optHR = { 'log' => 1, %dbOpt};
        $obj->loadOptions($optHR);
        ok($obj->{'_optHR'}->{'log'}, "log set if needed.");
    }
    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        $obj->loadOptions( \%dbOpt );
        ok(! $obj->{'_optHR'}->{'log'}, "log not set by default.");
    }

    # _argvAR
    {
        @ARGV = ('--verbose', '--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        # loadOptions called to do this...
        is_deeply($obj->{'_argvAR'}, ['--verbose', '--debug', @DEF_CLI], "ARGV was captured.");
    }

    # _optHR
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        # loadOptions called to do this...
        ok($obj->{'_optHR'}->{'debug'}, "optHR was captured.");
    }

    {
        my $message = "_argumentsAR loaded into object.";
        @ARGV = ('--verbose', @DEF_CLI);
        my $obj = $CLASS->new();
        # loadOptions called to do this...
        is_deeply($obj->{'_argumentsAR'}, ['status-local'], $message);
    }

    {
        my $message = 'Error if no --dbUser opt';
        my $obj = makeBam();
        my $optHR = {
            'dbPassword' => 'dummy', 'dbHost' => 'host', 'dbSchema' => 'dummy'
        };
        my $errorRE = qr/^--dbUser option required\./;
        throws_ok( sub { $obj->loadOptions($optHR); }, $errorRE, $message);
    }
    {
        my $message = 'Error if no --dbPassword opt';
        my $obj = makeBam();
        my $optHR = {
            'dbUser' => 'dummy', 'dbHost' => 'host', 'dbSchema' => 'dummy'
        };
        my $errorRE = qr/^--dbPassword option required\./;
        throws_ok( sub { $obj->loadOptions($optHR); }, $errorRE, $message);
    }
    {
        my $message = 'Error if no --dbHost opt';
        my $obj = makeBam();
        my $optHR = {
            'dbUser' => 'dummy', 'dbPassword' => 'dummy', 'dbSchema' => 'dummy'
        };
        my $errorRE = qr/^--dbHost option required\./;
        throws_ok( sub { $obj->loadOptions($optHR); }, $errorRE, $message);
    }
    {
        my $message = 'Error if no --dbSchema opt';
        my $obj = makeBam();
        my $optHR = {
            'dbUser' => 'dummy', 'dbPassword' => 'dummy', 'dbHost' => 'host'
        };
        my $errorRE = qr/^--dbSchema option required\./;
        throws_ok( sub { $obj->loadOptions($optHR); }, $errorRE, $message);
    }
}

sub testLoadArguments {
    plan( tests => 8 );

    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    {
        my $command = "status-local";
        $obj->loadArguments([$command]);
        {
            my $message = "1 arg = command";
            my $got = $obj->{'command'};
            my $want = $command;
            is( $got, $want, $message );
        }
        {
            my $message = "1 arg = no sample file";
            ok( ! $obj->{'sampleFile'}, $message);
        }
    }
    {
        my $command = "status-local";
        $obj->loadArguments([$command, $SAMPLE_FILE]);
        {
            my $message = "2 args: 1st = command";
            my $got = $obj->{'command'};
            my $want = $command;
            is( $got, $want, $message );
        }
        {
            my $message = "2 args: 2nd = sampleFile";
            my $got = $obj->{'sampleFile'};
            my $want = $SAMPLE_FILE;
            is( $got, $want, $message );
        }
    }
    {
        my $message = "error if no command specified";
        my $errorRE = qr/^Must specify a command\. Try --help\.\n/;
        throws_ok( sub { $obj->loadArguments([]); }, $errorRE, $message );
    }
    {
        my $message = "error if unknown command specified";
        my $command = "bad-command-oops";
        my $errorRE = qr/I don't know the command 'bad-command-oops'\. Try --help\.\n/;
        throws_ok( sub { $obj->loadArguments(['bad-command-oops']); }, $errorRE, $message );
    }
    {
        my $message = "error if 2nd argument is not an existing sample file";
        my $noSuchFile = $CLASS->getUuid();
        my $errorRE = qr/I can't find the sample file '$noSuchFile'\.\n/;
        throws_ok( sub { $obj->loadArguments(['status-local', $noSuchFile]); }, $errorRE, $message );
    }
    {
        my $message = "error if more than 2 arguments";
        my $command = "status-local";
        my $errorRE = qr/Too many arguments for cammand '$command'. Try --help.\n/;
        throws_ok( sub { $obj->loadArguments([$command, $SAMPLE_FILE, 'foo']); }, $errorRE, $message );
    }
}

sub testParseCli {
    plan( tests => 9 );
    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();

    # --verbose
    {
         my $message = "--verbose flag default is unset";
         @ARGV = @DEF_CLI;
         my $opt = $obj->parseCli();
         ok( ! $opt->{'verbose'}, $message );
    }
    {
         my $message = "--verbose flag can be set";
         @ARGV = ('--verbose', @DEF_CLI);
         my $opt = $obj->parseCli();
         ok( $opt->{'verbose'}, $message );
    }

    # --debug
    {
         my $message = "--debug flag default is unset";
         @ARGV = @DEF_CLI;
         my $opt = $obj->parseCli();
         ok( ! $opt->{'debug'}, $message );
    }
    {
         my $message = "--debug flag can be set";
         @ARGV = ('--debug', @DEF_CLI);
         my $opt = $obj->parseCli();
         ok( $opt->{'debug'}, $message );
    }

    # --log
    {
         my $message = "--log flag default is unset";
         @ARGV = @DEF_CLI;
         my $opt = $obj->parseCli();
         ok( ! $opt->{'log'}, $message );
    }
    {
         my $message = "--log flag can be set";
         @ARGV = ('--log', @DEF_CLI);
         my $opt = $obj->parseCli();
         ok( $opt->{'log'}, $message );
    }

    # --config
    {
         my $message = "--config default is set";
         @ARGV = @DEF_CLI;
         my $opt = $obj->parseCli();
         is( $opt->{'config'}, Bio::SeqWare::Config->getDefaultFile(), $message );
    }
    {
         my $message = "--config flag can be set";
         @ARGV = ('--config', 'some/new.cfg', @DEF_CLI);
         my $opt = $obj->parseCli();
         is( $opt->{'config'}, "some/new.cfg", $message );
    }

    {
        my $message = "key \"argumentsAR\" contains arguments";
        @ARGV = ('--verbose', '--debug', @DEF_CLI);
        my $opt = $obj->parseCli();
        is_deeply( $opt->{'argumentsAR'}, ['status-local'], $message );
    }

    # argumentsAR works if mixed, and with "--"
    # Add test later.
}

sub testSayAndSayDebugAndSayVerbose {
 
    plan( tests => 21 );

    # --debug set
    {
        @ARGV = ('--debug', @DEF_CLI);
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
        @ARGV = ('--verbose', @DEF_CLI);
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
        @ARGV = @DEF_CLI;
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
        @ARGV = ('--debug', @DEF_CLI);
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
        @ARGV = ('--debug', @DEF_CLI);
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
        @ARGV = ('--debug', @DEF_CLI);
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

    # --debug and --log set
    {
        @ARGV = ('--debug', '--log', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with debug on';
        my $timestampRES = '\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}';
        my $uuidRES = '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}';
        my $hostRES = '[^\s]+';
        my $levelRES = '(INFO|VERBOSE|DEBUG)';
        my $prefxRES = $hostRES . ' ' . $timestampRES . ' ' . $uuidRES . ' \[' . $levelRES . '\]';
        my $expectRE = qr/^$prefxRES $text\n$/m;
        {
            stdout_like { $obj->sayDebug(   $text ); } $expectRE, "--debug and sayDebug";
            stdout_like { $obj->sayVerbose( $text ); } $expectRE, "--debug and sayVerbose";
            stdout_like { $obj->say(        $text ); } $expectRE, "--debug and say";
        }
    }

}

sub testFixupTildePath {
    plan( tests => 5 );

    @ARGV = @DEF_CLI;
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
        @ARGV = @DEF_CLI;
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
            my $badFileName = $CLASS->getUuid() . ".notAnExistingFile";
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
        @ARGV = ('--config', "$TEST_CFG", @DEF_CLI);
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

sub testGetUuid {
    plan( tests => 3);

    my $uuid = $CLASS->getUuid();
    my $uuid2 = $CLASS->getUuid();
    like( $uuid, qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/, "uuid generated as string");
    like( $uuid2, qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/, "another uuid generated as string");
    isnt( $uuid, $uuid2, "two successive uuids are not the same");
}

sub testGetTimestamp {
    plan( tests => 2);

    {
        my $message = "New timestamp is generated correctly";
        my $got = $CLASS->getTimestamp();
        my $matchRE = qr/^\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}$/;
        like( $got, $matchRE, $message);
    }
    {
        my $message = "Provided timestamp is formatted correctly";
        my $got = $CLASS->getTimestamp( 0 );
        my $matchRE = qr/^\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}$/;
        # Can't test absolute due to time-zone local shifting.
        like( $got, $matchRE, $message);
    }
}

sub testGetLogPrefix {
    plan( tests => 1);

    my $obj = makeBam();

    my $message = "Log prefix is formatted correctly";
    my $got = $obj->getLogPrefix();
    my $timestampRES = '\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}';
    my $uuidRES = '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}';
    my $hostRES = '[^\s]+';
    my $levelRES = '(INFO|VERBOSE|DEBUG)';
    my $exectRE = qr(^$hostRES $timestampRES $uuidRES \[$levelRES\]$);
    like( $got, $exectRE, $message);
}

sub testLogifyMessage {
    plan( tests => 4 );

    my $obj = makeBam();
    my $timestampRES = '\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}';
    my $uuidRES = '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}';
    my $hostRES = '[^\s]+';
    my $levelRES = '(INFO|VERBOSE|DEBUG)';
    my $prefxRES = $hostRES . ' ' . $timestampRES . ' ' . $uuidRES . ' \[' . $levelRES . '\]';

    {
        my $message = 'Logify a single line message ending in \n';
        my $text = "Simple message line";
        my $got = $obj->logifyMessage("$text\n");
        my $expectRE = qr/^$prefxRES $text\n$/m;
        like($got, $expectRE, $message);
    }
    {
        my $message = 'Logify a multi-line message ending in \n';
        my $text1 = "Complex message";
        my $text2 = "\twith";
        my $text3 = "\tsome formating";
        my $expectRE = qr/^$prefxRES $text1\n$prefxRES $text2\n$prefxRES $text3\n$/m;
        my $got = $obj->logifyMessage("$text1\n$text2\n$text3\n");
        like($got, $expectRE, $message);
    }
    {
        my $message = 'Logify a single line message not ending in \n';
        my $text = "Simple message line";
        my $got = $obj->logifyMessage("$text");
        my $expectRE = qr/^$prefxRES $text\n$/m;
        like($got, $expectRE, $message);
    }
    {
        my $message = 'Logify a multi-line message not ending in \n';
        my $text1 = "Complex message";
        my $text2 = "\twith";
        my $text3 = "\tsome formating";
        my $expectRE = qr/^$prefxRES $text1\n$prefxRES $text2\n$prefxRES $text3\n$/m;
        my $got = $obj->logifyMessage("$text1\n$text2\n$text3");
        like($got, $expectRE, $message);
    }

}

sub makeBam {

    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    return $obj;
}

sub makeMockDbh {
    my $mockDbh = DBI->connect(
        'DBI:Mock:',
        '',
        '',
        { 'RaiseError' => 1, 'PrintError' => 0, 'AutoCommit' => 1, 'ShowErrorStatement' => 1 },
    );
    return $mockDbh;
}