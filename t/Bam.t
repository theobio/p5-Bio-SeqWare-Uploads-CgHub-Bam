#! /usr/bin/env perl

use Data::Dumper;                # Simple data structure printing
use Scalar::Util qw( blessed );  # Get class of objects

use Test::Output;                # Tests what appears on stdout.
use Test::More 'tests' => 25;    # Main test module; run this many subtests
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
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 status-local);

# Run these tests
subtest( 'new()'      => \&testNew );
subtest( 'run()'      => \&testRun );
subtest( 'parseCli()'    => \&testParseCli    );
subtest( 'loadOptions()'   => \&testLoadOptions );

subtest( 'loadArguments()' => \&testLoadArguments );
subtest( 'fixupTildePath()' => \&testFixupTildePath );
subtest( 'getConfigOptions()' => \&testGetConfigOptions );
subtest( 'say(),sayDebug(),SayVerbose(),sayError()' => \&testSayAndSayDebugAndSayVerboseAndSayError );
subtest( 'getUuid()'     => \&testGetUuid    );
subtest( 'getTimestamp()' => \&testGetTimestamp);
subtest( 'getLogPrefix()' => \&testGetLogPrefix);
subtest( 'logifyMessage()' => \&testLogifyMessage);
subtest( 'parseSampleFile()' => \&testParseSampleFile);
subtest( 'getDbh()'  => \&testGetDbh);
subtest( 'DESTROY()' => \&testDESTROY );
subtest( 'setUploadStatus()' => \&testSetUploadStatus );
subtest( 'setUDone()' => \&testSetDone );
subtest( 'setFail()' => \&testSetFail );
subtest( 'getErrorName()' => \&testGetErrorName );
subtest( 'dbGetBamFileInfo()' => \&testDbGetBamFileInfo );
subtest( 'ensureIsDefined()' => \&testEnsureIsDefined );
subtest( 'ensureIsntEmptyString()' => \&testEnsureIsntEmptyString );
subtest( 'checkCompatibleHash()' => \&testCheckCompatibleHash );

subtest( 'dbSetRunning()' => \&testDbSetRunning );
subtest( 'dbDie()' => \&testDbDie );


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
        $obj->{'dbh'}->disconnect();
        $obj->{'dbh'}->{mock_can_connect} = 0;
        undef $obj;  # Invokes DESTROY.
        is( $obj, undef, $message);
    }
    {
        my $message = "DESTROY dbh open";
        my $obj = makeBam();
        undef $obj;  # Invokes DESTROY.
        is( $obj, undef, $message);
    }
    {
        my $message = "DESTROY dbh open wth transaction";
        my $obj = makeBam();
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
        my $dbh = $obj->getDbh();
        my $got = blessed $dbh;
        my $want = "DBI::db";
        is( $got, $want, $message );
    }

    {
        my $message = "Error if failes to get connection";
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        my $module = new Test::MockModule( 'Bio::SeqWare::Db::Connection' );
        $module->mock( 'getConnection', sub { return undef } );
        my $errorRE = qr/^DbConnectException: Failed to connect to the database\./;
        throws_ok( sub { $obj->getDbh(); }, $errorRE, $message )
    }

    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
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
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        $obj = Test::MockObject::Extends->new( $obj );
        $obj->mock( 'getDbh', sub{ return makeMockDbh(); });
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

sub testSetFail {
    plan( tests => 4);
    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        $obj = Test::MockObject::Extends->new( $obj );
        $obj->mock( 'getDbh', sub{ return makeMockDbh(); });
        $obj->mock(
            'setUploadStatus',
            sub {
                my $self = shift;
                $self->{'_test_upload_id'} = shift;
                $self->{'_test_newStatus'} = shift;
                return 1;
            }
        );
        my $upload_id = 21;
        my $step = "dummy-status";
        my $recHR = {'upload_id' => $upload_id, 'ignoreMe' => 'yes'};
        my $error = "JokeException: Just kidding,\n";
        my $retVal = $obj->setFail( $recHR, $step, $error );
        {
            my $message = "Set fail returns error";
            my $got = $retVal;
            my $want = $error;
            is( $got, $want, $message );
        }
        {
            my $message = "passed upload_id to setUploadStatus";
            my $got = $obj->{'_test_upload_id'};
            my $want = $upload_id;
            is( $got, $want, $message );
        }
        {
            my $message = "passed new status correctly to setUploadStatus";
            my $got = $obj->{'_test_newStatus'};
            my $want = "dummy-status_failed_Joke";
            is( $got, $want, $message );
        }
    }

    # Test cascading exception.
    {
        my $obj = makeBam();
        $obj = Test::MockObject::Extends->new( $obj );
        my $dbError = "KaboomException: Ouch.\n";
        $obj->mock( 'setUploadStatus', sub { die $dbError; } );
        my $upload_id = 21;
        my $step = "dummy-status";
        my $recHR = {'upload_id' => $upload_id, 'ignoreMe' => 'yes'};
        my $error = "JokeException: Just kidding,\n";
        my $retVal = $obj->setFail( $recHR, $step, $error );
        {
            my $message = "Set fail with error returns cascade error message";
            my $got = $retVal;
            my $expectRE = qr/$dbError.*Tried to fail run because of:.*$error/s;
            like( $got, $expectRE, $message );
        }
    }
}

sub testDbGetBamFileInfo {
    plan( tests => 10);

    # Data
    my $sample      = "sample-name";
    my $flowcell    = "flowcell-name";
    my $lane_index  = 0;
    my $workflow_id = 39;
    my $barcode     = "AAGGTT";
    my $meta_type   = 'application/bam';
    my $type        = 'Mapsplice-sort';
    my $file_path   = '/my/file/path';
    my $file_id     = 5;
    my $sample_id   = 20;

    #Test with barcode
    {
        my $lookupHR = {
            'sample' => $sample, 'flowcell' => $flowcell, 'workflow_id' => 39,
            'lane_index' => $lane_index, 'barcode' => $barcode,
        };

        my $expectHR = {
         'sample' => $sample, 'file_path' => $file_path, 'file_id' => $file_id,
         'meta_type' => $meta_type, 'flowcell' => $flowcell,
         'lane_index' => $lane_index, 'barcode' => $barcode, 'type' => $type,
         'sample_id' => $sample_id, 'workflow_id' => $workflow_id
        };

        my @dbEvent = ({
            'statement'   => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
            'bound_params' => [ $meta_type, $type, $sample, $flowcell, $lane_index, $workflow_id, $barcode ],
            'results'  => [
                [ 'sample',     'file_path', 'file_id', 'meta_type', 'flowcell',
                  'lane_index', 'barcode',   'type',    'sample_id', 'workflow_id' ],
                [ $sample,      $file_path,  $file_id,  $meta_type,  $flowcell,
                  $lane_index,  $barcode,    $type,     $sample_id,  $workflow_id  ],
            ],
        });

        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'dbGetBamFileInfo', @dbEvent );
        {
            my $message = "dbGetBamFileInfo with good data works.";
            my $got = $obj->dbGetBamFileInfo( $lookupHR );
            my $want = $expectHR;
            is_deeply( $got, $want, $message );
        }
    }

    #Test without barcode
    {
        my $lookupHR = {
            'sample' => $sample, 'flowcell' => $flowcell, 'workflow_id' => 39,
            'lane_index' => $lane_index, 'barcode' => undef,
        };
        my $expectHR = {
         'sample' => $sample, 'file_path' => $file_path, 'file_id' => $file_id,
         'meta_type' => $meta_type, 'flowcell' => $flowcell,
         'lane_index' => $lane_index, 'barcode' => undef, 'type' => $type,
         'sample_id' => $sample_id, 'workflow_id' => $workflow_id
        };

        my @dbEventNoBarcode = ({
            'statement'   => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
            'bound_params' => [ $meta_type, $type, $sample, $flowcell, $lane_index, $workflow_id  ],
            'results'  => [
                [ 'sample',     'file_path', 'file_id', 'meta_type', 'flowcell',
                  'lane_index', 'barcode',   'type',    'sample_id', 'workflow_id' ],
                [ $sample,      $file_path,  $file_id,  $meta_type,  $flowcell,
                  $lane_index,  undef,    $type,     $sample_id,  $workflow_id  ],
            ],
        });

        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'dbGetBamFileInfoNoBarcode', @dbEventNoBarcode );
        {
            my $message = "dbGetBamFileInfo with good data no barcodeworks.";
            my $got = $obj->dbGetBamFileInfo( $lookupHR );
            my $want = $expectHR;
            is_deeply( $got, $want, $message );
        }
    }

    # Test fail with bad input
    {
        my $lookupHR = {
            'sample' => $sample, 'flowcell' => $flowcell, 'workflow_id' => 39,
            'lane_index' => $lane_index, 'barcode' => $barcode,
        };

        my $obj = makeBam();
        {
            my $message = "Missing sample name";
            my %badRec = %$lookupHR;
            $badRec{sample} = undef;
            my $errorRE = qr/^BadDataException: Missing sample name\./;
            throws_ok( sub {$obj->dbGetBamFileInfo( \%badRec ) }, $errorRE, $message);
        }
        {
            my $message = "Missing flowcell name";
            my %badRec = %$lookupHR;
            $badRec{flowcell} = '';
            my $errorRE = qr/^BadDataException: Missing flowcell name\./;
            throws_ok( sub {$obj->dbGetBamFileInfo( \%badRec ) }, $errorRE, $message);
        }
        {
            my $message = "Missing lane_index";
            my %badRec = %$lookupHR;
            delete $badRec{'lane_index'};
            my $errorRE = qr/^BadDataException: Missing lane_index\./;
            throws_ok( sub {$obj->dbGetBamFileInfo( \%badRec ) }, $errorRE, $message);
        }
        {
            my $message = "Missing workflow_id";
            my %badRec = %$lookupHR;
            $badRec{workflow_id} = undef;
            my $errorRE = qr/^BadDataException: Missing workflow_id\./;
            throws_ok( sub {$obj->dbGetBamFileInfo( \%badRec ) }, $errorRE, $message);
        }
        {
            my $message = "Barcode is empty, not undefined";
            my %badRec = %$lookupHR;
            $badRec{barcode} = '';
            my $errorRE = qr/^BadDataException: Barcode must be undef, not empty sting\./;
            throws_ok( sub {$obj->dbGetBamFileInfo( \%badRec ) }, $errorRE, $message);
        }
        {
            my $message = "Missing barcode";
            my %badRec = %$lookupHR;
            delete $badRec{'barcode'};
            my $errorRE = qr/^BadDataException: Unspecified barcode\./;
            throws_ok( sub {$obj->dbGetBamFileInfo( \%badRec ) }, $errorRE, $message);
        }
    }

    # Test mismatch query/return info
    #Test with barcode
    {
        my $lookupHR = {
            'sample' => $sample, 'flowcell' => $flowcell, 'workflow_id' => 39,
            'lane_index' => $lane_index, 'barcode' => $barcode, 'file_path' => 'BAD'
        };

        my $expectHR = {
         'sample' => $sample, 'file_path' => $file_path, 'file_id' => $file_id,
         'meta_type' => $meta_type, 'flowcell' => $flowcell,
         'lane_index' => $lane_index, 'barcode' => $barcode, 'type' => $type,
         'sample_id' => $sample_id, 'workflow_id' => $workflow_id
        };

        my @dbMismatchedEvent = ({
            'statement'   => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
            'bound_params' => [ $meta_type, $type, $sample, $flowcell, $lane_index, $workflow_id, $barcode ],
            'results'  => [
                [ 'sample',     'file_path', 'file_id', 'meta_type', 'flowcell',
                  'lane_index', 'barcode',   'type',    'sample_id', 'workflow_id' ],
                [ $sample,      $file_path,  $file_id,  $meta_type,  $flowcell,
                  $lane_index,  $barcode,    $type,     $sample_id,  $workflow_id  ],
            ],
        });

        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'dbGetBamFileInfoMismatched', @dbMismatchedEvent );
        {
            my $message = "Error in dbGetBamFileInfo with mismatched query data.";
            my $part1 = 'DbMismatchException: Queried .1. and returned .2. hashes differ unexpectedly:';
            my $part2 = 'file_path.*BAD.*\/my\/file\/path';
            my $part3 = 'Query:.*Parameters';
            my $errorRE = qr/^$part1.*$part2.*$part3/s;
            throws_ok( sub { $obj->dbGetBamFileInfo( $lookupHR ) }, $errorRE, $message);
        }
    }

    #Die with two records retrieved.
    {
        my $lookupHR = {
            'sample' => $sample, 'flowcell' => $flowcell, 'workflow_id' => 39,
            'lane_index' => $lane_index, 'barcode' => $barcode,
        };

        my $expectHR = {
         'sample' => $sample, 'file_path' => $file_path, 'file_id' => $file_id,
         'meta_type' => $meta_type, 'flowcell' => $flowcell,
         'lane_index' => $lane_index, 'barcode' => $barcode, 'type' => $type,
         'sample_id' => $sample_id, 'workflow_id' => $workflow_id
        };

        my @dbDupEvent = ({
            'statement'   => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
            'bound_params' => [ $meta_type, $type, $sample, $flowcell, $lane_index, $workflow_id, $barcode ],
            'results'  => [
                [ 'sample',     'file_path', 'file_id', 'meta_type', 'flowcell',
                  'lane_index', 'barcode',   'type',    'sample_id', 'workflow_id' ],
                [ $sample,      $file_path,  $file_id,  $meta_type,  $flowcell,
                  $lane_index,  $barcode,    $type,     $sample_id,  $workflow_id  ],
                [ $sample,      $file_path,  $file_id,  $meta_type,  $flowcell,
                  $lane_index,  $barcode,    $type,     $sample_id,  $workflow_id  ],
            ],
        });

        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'getBamDupFileInfo', @dbDupEvent );
        {
            my $message = "dbGetBamFileInfo with duplicate return failure.";
            my $part1 = 'DbDuplicateException: More than one record returned';
            my $part2 = 'Query: ';
            my $part3 = 'Parameters: ';
            my $errorRE = qr/^$part1\n$part2.*$part3/ms;
            throws_ok( sub { $obj->dbGetBamFileInfo( $lookupHR ) }, $errorRE, $message);
        }
    }
    
}

sub testRun {
    plan( tests => 3 );

    {
        my $message = "run succeeds";
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        my $want = 1;
        my $got = $obj->run();
        is( $got, $want, $message );
    }
    {
        my $message = "run fails quietly if logging.";
        @ARGV = (@DEF_CLI, '--log');
        my $obj = $CLASS->new();
        $obj->{'command'} = 'NoSuchFunctionCommand';
        my $want = 0;
        my $got = $obj->run();
        is( $got, $want, $message );
    }
    {
        my $message = "Run fails noisily if not logging error message.";
        @ARGV = (@DEF_CLI);
        my $obj = $CLASS->new();
        $obj->{'command'} = undef;
        my $matchRE = qr/Use of uninitialized value in hash element/;
        throws_ok( sub {$obj->run();}, $matchRE, $message );
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
            { sample => 'TCGA1', flowcell => 'UNC1', lane => 6, barcode => undef, bam_file => undef },
            { sample => 'TCGA2', flowcell => 'UNC2', lane => 7, barcode => 'ATTCGG', bam_file => undef },
            { sample => 'TCGA3', flowcell => 'UNC3', lane => 8, barcode => 'ATTCGG', bam_file => '/not/really' },
            { sample => 'TCGA4', flowcell => 'UNC4', lane => 1, barcode => undef, bam_file => '/old/fake' },
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
            { sample => 'TCGA1', flowcell => 'UNC1', lane => 6, barcode => undef },
            { sample => 'TCGA2', flowcell => 'UNC2', lane => 7, barcode => 'ATTCGG' },
            { sample => 'TCGA3', flowcell => 'UNC3', lane => 8, barcode => 'ATTCGG' },
            { sample => 'TCGA4', flowcell => 'UNC4', lane => 1, barcode => undef },
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
    plan( tests => 19 );

    my %reqOpt = (
        'dbUser' => 'dummy', 'dbPassword' => 'dummy',
        'dbHost' => 'host', 'dbSchema' => 'dummy', 'workflow_id' => 38
    );

    # --verbose only
    {
        @ARGV = ('--verbose', @DEF_CLI);
        my $obj = $CLASS->new();
        my $optHR = {'verbose' => 1, %reqOpt};
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
        my $optHR = {'debug' => 1, %reqOpt};
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
        my $optHR = {'verbose' => 1, 'debug' => 1, %reqOpt};
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
        my $optHR = { 'log' => 1, %reqOpt};
        $obj->loadOptions($optHR);
        ok($obj->{'_optHR'}->{'log'}, "log set if needed.");
    }
    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        $obj->loadOptions( \%reqOpt );
        ok(! $obj->{'_optHR'}->{'log'}, "log not set by default.");
    }

    # --workflow_id
    {
        @ARGV = ('--log', @DEF_CLI);
        my $obj = $CLASS->new();
        ok($obj->{'workflow_id'} = 38, "workflow id is set.");
    }
    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        $obj->loadOptions( \%reqOpt );
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

    # Required options
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
    {
        my $message = 'Error if no --workflow_id opt';
        my $obj = makeBam();
        my $optHR = {
            'dbUser' => 'dummy', 'dbPassword' => 'dummy', 'dbHost' => 'host',
            'dbSchema' => 'dummy'
        };
        my $errorRE = qr/^--workflow_id option required\./;
        throws_ok( sub { $obj->loadOptions($optHR); }, $errorRE, $message);
    }
    {
        my $message = 'Error if bad --workflow_id opt (41)';
        my $obj = makeBam();
        my $optHR = {
            'dbUser' => 'dummy', 'dbPassword' => 'dummy', 'dbHost' => 'host',
            'dbSchema' => 'dummy', 'workflow_id' => 41
        };
        my $errorRE = qr/^--workflow_id must be 38, 39, or 40\./;
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

sub testSayAndSayDebugAndSayVerboseAndSayError {
 
    plan( tests => 32 );

    # --debug set
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with debug on';
        my $expectRE = qr/^$text/;
        {
            stdout_like   { $obj->sayDebug(   $text ); } $expectRE, "--debug and sayDebug";
            stdout_like   { $obj->sayVerbose( $text ); } $expectRE, "--debug and sayVerbose";
            stdout_like   { $obj->say(        $text ); } $expectRE, "--debug and say";
            throws_ok(sub { $obj->sayError(   $text ); },$expectRE, "--debug and sayError");
        }
    }

    # --verbose set
    {
        @ARGV = ('--verbose', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with verbose on';
        my $expectRE = qr/^$text/;
        {
            stdout_unlike { $obj->sayDebug(   $text ); } $expectRE, "--verbose and sayDebug";
            stdout_like   { $obj->sayVerbose( $text ); } $expectRE, "--verbose and sayVerbose";
            stdout_like   { $obj->say(        $text ); } $expectRE, "--verbose and say";
            throws_ok(sub { $obj->sayError(   $text ); },$expectRE, "--verbose and sayError");
        }
    }

    # --no flag set
    {
        @ARGV = @DEF_CLI;
        my $obj = $CLASS->new();
        my $text = 'Say with no flag';
        my $expectRE = qr/^$text/;
        {
            stdout_unlike { $obj->sayDebug(   $text ); } $expectRE, "no flag and sayDebug";
            stdout_unlike { $obj->sayVerbose( $text ); } $expectRE, "no flag and sayVerbose";
            stdout_like   { $obj->say(        $text ); } $expectRE, "no flag and say";
            throws_ok(sub { $obj->sayError(   $text ); },$expectRE, "no flag and sayError");

        }
    }

    # $object parameter is string.
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with scalar object.';
        my $object = 'The second object';
        my $expect = "$text\n$object";
        my $expectRE = qr/$text\n$object/m;
        {
            stdout_is     { $obj->sayDebug(   $text, $object ); } $expect, "--Scalar object and sayDebug";
            stdout_is     { $obj->sayVerbose( $text, $object ); } $expect, "--Scalar object and sayVerbose";
            stdout_is     { $obj->say(        $text, $object ); } $expect, "--Scalar object and say";
            throws_ok(sub { $obj->sayError(   $text, $object ); },$expectRE, "--Scalar object and sayError");
        }
    }

    # $object parameter is hashRef.
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with hashRef object.';
        my $object = {'key'=>'value'};
        my $objectString = Dumper($object);
        my $expect   =   "$text\n$objectString";
        my $objectForRE = "\\" . $objectString;
        my $expectRE = qr/$text\n$objectForRE/m;
        {
            stdout_is     { $obj->sayDebug(   $text, $object ); } $expect, "HashRef object and sayDebug";
            stdout_is     { $obj->sayVerbose( $text, $object ); } $expect, "HashRef object and sayVerbose";
            stdout_is     { $obj->say(        $text, $object ); } $expect, "HashRef object and say";
            throws_ok(sub { $obj->sayError(   $text, $object ); },$expectRE, "HashRef object and sayError");
        }
    }

    # $object parameter is arrayRef.
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with arrayRef object.';
        my $object = ['key', 'value'];
        my $objectString = Dumper($object);
        my $expect   =   "$text\n$objectString";
        my $objectForRE = "\\" . $objectString;
        $objectForRE = join( '\[', split( '\[', $objectForRE ));
        $objectForRE = join( '\]', split( '\]', $objectForRE ));
        my $expectRE = qr/$text\n$objectForRE/m;
        {
            stdout_is     { $obj->sayDebug(   $text, $object ); } $expect, "ArrayRef object and sayDebug";
            stdout_is     { $obj->sayVerbose( $text, $object ); } $expect, "ArrayRef object and sayVerbose";
            stdout_is     { $obj->say(        $text, $object ); } $expect, "ArrayRef object and say";
            throws_ok(sub { $obj->sayError(   $text, $object ); },$expectRE, "ArrayRef object and sayError");
        }
    }

    # $object parameter is object.
    {
        @ARGV = ('--debug', @DEF_CLI);
        my $obj = $CLASS->new();
        my $text = 'Say with hashRef object.';
        my $object = $obj;
        my $objectString = blessed $obj;
        my $expectRE   =  qr/$text\n$objectString - /;
        {
            stdout_like   { $obj->sayDebug(   $text, $object ); } $expectRE, "Object object and sayDebug";
            stdout_like   { $obj->sayVerbose( $text, $object ); } $expectRE, "Object object and sayVerbose";
            stdout_like   { $obj->say(        $text, $object ); } $expectRE, "Object object and say";
            throws_ok(sub { $obj->sayError(   $text, $object ); },$expectRE, "Object object and sayError");
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
        my $prefxRES = $hostRES . ' ' . $timestampRES . ' ' . $uuidRES;
        
        {
            my $expectRE = qr/^$prefxRES \[DEBUG\] $text\n$/m;
            stdout_like { $obj->sayDebug(   $text ); } $expectRE, "--debug and sayDebug";
        }
        {
            my $expectRE = qr/^$prefxRES \[VERBOSE\] $text\n$/m;
            stdout_like { $obj->sayVerbose( $text ); } $expectRE, "--debug and sayVerbose";
        }
        {
            my $expectRE = qr/^$prefxRES \[INFO\] $text\n$/m;
            stdout_like { $obj->say(        $text ); } $expectRE, "--debug and say";
        }
        {
            my $expectRE = qr/^$prefxRES \[ERROR\] $text\n$/m;
            stdout_like { $obj->sayError(   $text ); } $expectRE, "--debug and sayError";
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

sub testGetErrorName {
    plan( tests => 4);
    {
        my $message = "Exception name parsed correctly";
        my $got = $CLASS->getErrorName( "SomeTestException: It blew up!" );
        my $want = "SomeTest";
        is( $got, $want, $message);
    }
    {
        my $message = "Error name parsed correctly";
        my $got = $CLASS->getErrorName( "testerror: It blew up!" );
        my $want = "test";
        is( $got, $want, $message);
    }
    {
        my $message = "Nested exceptions parsed correctly";
        my $got = $CLASS->getErrorName( "SomeTestException: It blew up! Also - BADException." );
        my $want = "SomeTest";
        is( $got, $want, $message);
    }
    {
        my $message = "Default Exception name";
        my $got = $CLASS->getErrorName( "SomeTestExcepton: Spelling matters!." );
        my $want = "Unknown";
        is( $got, $want, $message);
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

sub testEnsureIsDefined {
    plan( tests => 6);

    my $testError = "FakeException: No so bad\n";
    my $definedFalseValue = 0;
    my $definedTrueValue = "Hello";
    my $expectMyErrorRE = qr/^$testError/m;
    my $expectDefaultErrorRE = qr/^ValidationErrorNotDefined: Expected a defined value\.\n/m;
    {
        my $message = "Returns value if defined and false with error";
        my $got = $CLASS->ensureIsDefined( $definedFalseValue, $testError );
        my $want = $definedFalseValue;
        is( $got, $want, $message)
    }
    {
        my $message = "Returns value if defined and true with error";
        my $got = $CLASS->ensureIsDefined( $definedTrueValue, $testError );
        my $want = $definedTrueValue;
        is( $got, $want, $message)
    }
    {
        my $message = "Returns value if defined and false without error ";
        my $got = $CLASS->ensureIsDefined( $definedFalseValue );
        my $want = $definedFalseValue;
        is( $got, $want, $message)
    }
    {
        my $message = "Returns value if defined and true without error";
        my $got = $CLASS->ensureIsDefined( $definedTrueValue );
        my $want = $definedTrueValue;
        is( $got, $want, $message)
    }
    {
        my $message = "Dies with provided message if value not defined";
        throws_ok( sub { $CLASS->ensureIsDefined( undef, $testError ) }, $expectMyErrorRE, $message);
    }
    {
        my $message = "Dies with default message if value not defined and no error.";
        throws_ok( sub { $CLASS->ensureIsDefined( undef ) }, $expectDefaultErrorRE, $message);
    }
}

sub testEnsureIsntEmptyString {
    plan( tests => 8);

    my $testError = "FakeException: No so bad\n";
    my $definedFalseNotEmpty = 0;
    my $definedNotEmpty = "Hello";
    my $expectMyErrorRE = qr/^$testError/m;
    my $expectDefaultErrorRE = qr/^ValidationErrorBadString: Expected a non-empty string\.\n/m;
    {
        my $message = "Returns value if defined and false with error";
        my $got = $CLASS->ensureIsntEmptyString( $definedFalseNotEmpty, $testError );
        my $want = $definedFalseNotEmpty;
        is( $got, $want, $message)
    }
    {
        my $message = "Returns value if defined and true with error";
        my $got = $CLASS->ensureIsntEmptyString( $definedNotEmpty, $testError );
        my $want = $definedNotEmpty;
        is( $got, $want, $message)
    }
    {
        my $message = "Returns value if defined and false without error ";
        my $got = $CLASS->ensureIsntEmptyString( $definedFalseNotEmpty );
        my $want = $definedFalseNotEmpty;
        is( $got, $want, $message)
    }
    {
        my $message = "Returns value if defined and true without error";
        my $got = $CLASS->ensureIsntEmptyString( $definedNotEmpty );
        my $want = $definedNotEmpty;
        is( $got, $want, $message)
    }
    {
        my $message = "Dies with provided message if value not defined";
        throws_ok( sub { $CLASS->ensureIsntEmptyString( undef, $testError ) }, $expectMyErrorRE, $message);
    }
    {
        my $message = "Dies with default message if value not defined and no error.";
        throws_ok( sub { $CLASS->ensureIsntEmptyString( undef ) }, $expectDefaultErrorRE, $message);
    }
    {
        my $message = "Dies with provided message if value is empty string";
        throws_ok( sub { $CLASS->ensureIsntEmptyString( '', $testError ) }, $expectMyErrorRE, $message);
    }
    {
        my $message = "Dies with default message if value is empty string and no error.";
        throws_ok( sub { $CLASS->ensureIsntEmptyString( "" ) }, $expectDefaultErrorRE, $message);
    }
}

sub testCheckCompatibleHash {
    plan( tests => 36);

    is( $CLASS->checkCompatibleHash( undef, undef ), undef );

    is( $CLASS->checkCompatibleHash( undef, {}    ), undef );
    is( $CLASS->checkCompatibleHash( {},    {}    ), undef );
    is( $CLASS->checkCompatibleHash( {},    undef ), undef );

    is( $CLASS->checkCompatibleHash( undef,  {A=>1} ), undef );
    is( $CLASS->checkCompatibleHash( {},     {A=>1} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1}, {A=>1} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1}, undef  ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1}, {}     ), undef );

    is( $CLASS->checkCompatibleHash( undef,       {A=>1,B=>2} ), undef );
    is( $CLASS->checkCompatibleHash( {},          {A=>1,B=>2} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1},      {A=>1,B=>2} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1,B=>2}, {A=>1,B=>2} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1,B=>2}, undef       ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1,B=>2}, {}          ), undef );
    is( $CLASS->checkCompatibleHash( {A=>1,B=>2}, {A=>1}      ), undef );

    is( $CLASS->checkCompatibleHash( undef,       {A=>undef}  ), undef );
    is( $CLASS->checkCompatibleHash( {},          {A=>undef}  ), undef );
    is_deeply( $CLASS->checkCompatibleHash( {A=>1},      {A=>undef}  ), {A=>[1,undef]} );
    is_deeply( $CLASS->checkCompatibleHash( {A=>1,B=>2}, {A=>undef}  ), {A=>[1,undef]} );
    is( $CLASS->checkCompatibleHash( {A=>undef},  {A=>undef}  ), undef );
    is( $CLASS->checkCompatibleHash( {A=>undef},  undef       ), undef );
    is( $CLASS->checkCompatibleHash( {A=>undef},  {}          ), undef );
    is_deeply( $CLASS->checkCompatibleHash( {A=>undef},  {A=>1}      ), {A=>[undef,1]} );
    is_deeply( $CLASS->checkCompatibleHash( {A=>undef},  {A=>1,B=>2} ), {A=>[undef,1]} );

    is( $CLASS->checkCompatibleHash( undef,           {A=>undef,B=>9} ), undef );
    is( $CLASS->checkCompatibleHash( {},              {A=>undef,B=>9} ), undef );
    is_deeply( $CLASS->checkCompatibleHash( {A=>1},          {A=>undef,B=>9} ), {A=>[1,undef]} );
    is_deeply( $CLASS->checkCompatibleHash( {A=>1,B=>2},     {A=>undef,B=>9} ), {A=>[1,undef],B=>[2,9]} );
    is( $CLASS->checkCompatibleHash( {A=>undef},      {A=>undef,B=>9} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>undef,B=>9}, {A=>undef,B=>9} ), undef );
    is( $CLASS->checkCompatibleHash( {A=>undef,B=>9}, undef           ), undef );
    is( $CLASS->checkCompatibleHash( {A=>undef,B=>9}, {}              ), undef );
    is_deeply( $CLASS->checkCompatibleHash( {A=>undef,B=>9}, {A=>1}          ), {A=>[undef,1]} );
    is_deeply( $CLASS->checkCompatibleHash( {A=>undef,B=>9}, {A=>1,B=>2}     ), {A=>[undef,1],B=>[9,2]} );
    is( $CLASS->checkCompatibleHash( {A=>undef,B=>9}, {A=>undef}      ), undef );

}

sub testGetLogPrefix {
    plan( tests => 2);

    my $obj = makeBam();
    my $timestampRES = '\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}';
    my $uuidRES = '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}';
    my $hostRES = '[^\s]+';

    {
        my $message = "Log prefix is formatted correctly for ERROR messages";
        my $level= 'ERROR';
        my $got = $obj->getLogPrefix($level);
        my $exectRE = qr(^$hostRES $timestampRES $uuidRES \[$level\]$);
        like( $got, $exectRE, $message);

    }
    {
        my $message = "Log prefix is formatted correctly for DEBUG messages";
        my $level= 'DEBUG';
        my $got = $obj->getLogPrefix($level);
        my $exectRE = qr(^$hostRES $timestampRES $uuidRES \[$level\]$);
        like( $got, $exectRE, $message);

    }

}
sub testLogifyMessage {
    plan( tests => 4 );

    my $obj = makeBam();
    my $timestampRES = '\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}';
    my $uuidRES = '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}';
    my $hostRES = '[^\s]+';
    my $prefxRES = $hostRES . ' ' . $timestampRES . ' ' . $uuidRES;

    {
        my $message = 'Logify a single line ERROR message ending in \n';
        my $text = "Simple message line";
        my $level = 'INFO';
        my $got = $obj->logifyMessage($level, "$text\n");
        my $expectRE = qr/^$prefxRES \[$level\] $text\n$/m;
        like($got, $expectRE, $message);
    }
    {
        my $message = 'Logify a multi-line VERBOSE message ending in \n';
        my $text1 = "Complex message";
        my $text2 = "\twith";
        my $text3 = "\tsome formating";
        my $level = 'VERBOSE';
        my $expectRE = qr/^$prefxRES \[$level\] $text1\n$prefxRES \[$level\] $text2\n$prefxRES \[$level\] $text3\n$/m;
        my $got = $obj->logifyMessage($level, "$text1\n$text2\n$text3\n");
        like($got, $expectRE, $message);
    }
    {
        my $message = 'Logify a single line ERROR message not ending in \n';
        my $text = "Simple message line";
        my $level = 'ERROR';
        my $got = $obj->logifyMessage($level, "$text");
        my $expectRE = qr/^$prefxRES \[$level\] $text\n$/m;
        like($got, $expectRE, $message);
    }
    {
        my $message = 'Logify a multi-line DEBUG message not ending in \n';
        my $text1 = "Complex message";
        my $text2 = "\twith";
        my $text3 = "\tsome formating";
        my $level = 'DEBUG';
        my $expectRE = qr/^$prefxRES \[$level\] $text1\n$prefxRES \[$level\] $text2\n$prefxRES \[$level\] $text3\n$/m;
        my $got = $obj->logifyMessage($level, "$text1\n$text2\n$text3");
        like($got, $expectRE, $message);
    }

}

sub testDbDie {
    plan( tests => 24 );

    # Normal db object
    {
        my $obj = makeBam();

        {
           my $message = "dbh in expected state";
           ok($obj->{'dbh'} && $obj->{'dbh'}->{'Active'} && $obj->{'dbh'}->{'AutoCommit'}, $message);
        }

        eval {
            $obj->dbDie("TestingDbDieException: Plain message");
        };

        {
            my $message = "Will throw plain error";
            my $got = $@;
            $matchRE = qr/^TestingDbDieException: Plain message/;
            like($got, $matchRE, $message);
        }
        {
            my $message = "dbh is cleared";
            is($obj->{'dbh'}, undef, $message);
        }
        {
            my $message = "dbh still exists";
            ok(exists $obj->{'dbh'}, $message);
        }
    }

    # Db Object in transaction, with message and rollback failure.
    {
        my $obj = makeBam();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql =>  "BEGIN WORK",
            results => [[]]
        };
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql =>  "ROLLBACK",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Force rollback failure.' ],
        };

        $obj->{'dbh'}->begin_work();
        {
           my $message = "dbh in expected state";
           ok($obj->{'dbh'} && $obj->{'dbh'}->{'Active'} && ! $obj->{'dbh'}->{'AutoCommit'}, $message);
        }

        $obj->{'verbose'} = 1;
        eval {
            $obj->dbDie("TestingDbDieException: In medias transaction.\n");
        };

        {
            my $message = "Will throw error and try to do rollback, with abort";
            my $got = $@;
            $matchRE = qr/^TestingDbDieException: In medias transaction.*Also:.*DbRollbackException: Rollback failed because of:.*Force rollback failure/s;
            like($got, $matchRE, $message);
        }
        {
            my $message = "dbh is cleared";
            is($obj->{'dbh'}, undef, $message);
        }
        {
            my $message = "dbh still exists";
            ok(exists $obj->{'dbh'}, $message);
        }
    }

    # Db Object in transaction, with message.
    {
        my $obj = makeBam();
        $obj->{'dbh'}->begin_work();
        {
           my $message = "dbh in expected state";
           ok($obj->{'dbh'} && $obj->{'dbh'}->{'Active'} && ! $obj->{'dbh'}->{'AutoCommit'}, $message);
        }

        $obj->{'verbose'} = 1;
        eval {
            $obj->dbDie("TestingDbDieException: In medias transaction.");
        };

        {
            my $message = "Will throw error and try to do rollback, with message";
            my $got = $@;
            $matchRE = qr/^TestingDbDieException: In medias transaction.*Rollback was performed/s;
            like($got, $matchRE, $message);
        }
        {
            my $message = "dbh is cleared";
            is($obj->{'dbh'}, undef, $message);
        }
        {
            my $message = "dbh still exists";
            ok(exists $obj->{'dbh'}, $message);
        }
    }

    # Db Object in transaction, without message.
    {
        my $obj = makeBam();
        $obj->{'dbh'}->begin_work();
        {
           my $message = "dbh in expected state";
           ok($obj->{'dbh'} && $obj->{'dbh'}->{'Active'} && ! $obj->{'dbh'}->{'AutoCommit'}, $message);
        }

        $obj->{'verbose'} = 0;
        eval {
            $obj->dbDie("TestingDbDieException: In medias transaction.");
        };

        {
            my $message = "Will throw error and try to do rollback, without message";
            my $got = $@;
            $matchRE = qr/^TestingDbDieException: In medias transaction\./;
            like($got, $matchRE, $message);
        }
        {
            my $message = "dbh is cleared";
            is($obj->{'dbh'}, undef, $message);
        }
        {
            my $message = "dbh still exists";
            ok(exists $obj->{'dbh'}, $message);
        }
    }

    # Db Object not active.
    {
        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_can_connect'} = 0;
        {
           my $message = "dbh in expected state";
           ok($obj->{'dbh'} && ! $obj->{'dbh'}->{'Active'}, $message);
        }

        $obj->{'verbose'} = 0;
        eval {
            $obj->dbDie("TestingDbDieException: Not active.");
        };

        {
            my $message = "Will throw error when not active";
            my $got = $@;
            $matchRE = qr/^TestingDbDieException: Not active\./;
            like($got, $matchRE, $message);
        }
        {
            my $message = "dbh is cleared";
            is($obj->{'dbh'}, undef, $message);
        }
        {
            my $message = "dbh still exists";
            ok(exists $obj->{'dbh'}, $message);
        }
    }
    # Db Object not present.
    {
        my $obj = makeBam();
        $obj->{'dbh'} = undef;
        {
           my $message = "dbh in expected state";
           ok( ! $obj->{'dbh'}, $message);
        }

        $obj->{'verbose'} = 0;
        eval {
            $obj->dbDie("TestingDbDieException: Not present.");
        };

        {
            my $message = "Will throw error when not present";
            my $got = $@;
            $matchRE = qr/^TestingDbDieException: Not present\./;
            like($got, $matchRE, $message);
        }
        {
            my $message = "dbh is cleared";
            is($obj->{'dbh'}, undef, $message);
        }
        {
            my $message = "dbh still exists";
            ok(exists $obj->{'dbh'}, $message);
        }
    }

}

sub testDbSetRunning {
    plan( tests => 6 );

    my $oldStep = "dummy";
    my $newStep = "dummy2";
    my $oldStatus = $oldStep . "_done";
    my $newStatus = $newStep . "_running";
    my $upload_id = 21;
    my $sample_id = 19;

    # valid run - found something.
    {
        my @dbEvents = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ $oldStatus ],
                'results'  => [
                    ['upload_id', 'status', 'sample_id' ],
                    [$upload_id, $oldStatus, $sample_id],
                ],
            },
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ $newStatus, $upload_id ],
                'results'  => [ [ 'rows' ], [] ],
            },
            dbMockStep_Commit()
        );
        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithReturn', @dbEvents );

        my $got; # Saving between tests as trouble to reset mockdb.
        {
            my $message = "Says nothing about nothing to do.";
            my $expectRE = qr/Nothing to do/;
            stdout_unlike( sub { $got = $obj->dbSetRunning( $oldStep, $newStep ); }, $expectRE, $message);
        }
        {
            my $message = "dbSetRunning with good data recovers record.";
            my $want = {'upload_id' => $upload_id, 'status' => $newStatus, 'sample_id' => $sample_id };
            is_deeply( $got, $want, $message );
        }
    }

    # valid run - found nothing.
    {
        my @dbEventsNothingToDo = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ $oldStatus ],
                'results'  => [[]],
            },
            dbMockStep_Commit()
        );
        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithNothingToDo', @dbEventsNothingToDo );

        my $got; # Saving between tests as trouble to reset mockdb.

        {
            my $message = "Says something about nothing to do.";
            my $expectRE = qr/Nothing to do\./;
            stdout_like( sub { $got = $obj->dbSetRunning( $oldStep, $newStep ); }, $expectRE, $message);
        }
        {
            my $message = "dbSetRunning with nothing to do.";
            my $want = undef;
            is( $got, $want, $message );
        }
    }


    # invalid - error thrown if die while updating.
    {
        my @dbEvents = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ $oldStatus ],
                'results'  => [
                    ['upload_id', 'status', 'sample_id' ],
                    [$upload_id, $oldStatus, $sample_id],
                ],
            },
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ $newStatus, $upload_id ],
                'results'  => [ [ 'rows' ], ],
            },
            dbMockStep_Rollback()
        );
        my $obj = makeBam();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithReturn', @dbEvents );
        {
            my $message = "dbSetRunning error if update fails.";
            my $errorRE = qr/^DbSetRunningException: Failed to select lane to run because of:/;
            throws_ok( sub { $obj->dbSetRunning( $oldStep, $newStep ); }, $errorRE, $message );
        }
    }

    # invalid - error thrown if die and can't rollback reported
    {
        my $obj = makeBam();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql => "BEGIN WORK",
            results => [[]],
        };
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql => "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE",
            results => [[]],
        };
        $obj->{'dbh'}->{mock_add_resultset} = [
            ['upload_id', 'status', 'sample_id' ],
            [$upload_id, $oldStatus, $sample_id],
        ];
        $obj->{'dbh'}->{mock_add_resultset} = [ [ 'rows' ], ];
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql => "ROLLBACK",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Trigger bad rollback.' ],
        };
        {
            my $message = "Error ifdbSetRunning roolback failes after failed update.";
            my $errorRES1 = 'DbSetRunningException: Failed to select lane to run because of:';
            my $errorRES2 = 'DbRollbackException: Rollback failed because of:';
            my $errorRES3 = 'Trigger bad rollback';
            my $errorRE = qr/^$errorRES1.*$errorRES2.*$errorRES3/sm;
            throws_ok( sub { $obj->dbSetRunning( $oldStep, $newStep ); }, $errorRE, $message );
        }
    }
}

sub makeBam {

    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    $obj->{'dbh'} = makeMockDbh();
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

sub dbMockStep_Begin {
    return {
        'statement' => 'BEGIN WORK',
        'results'   => [ [] ],
    };
}

sub dbMockStep_SetTransactionLevel {
    return {
        'statement' => 'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE',
        'results'  => [ [] ],
    };
}

sub dbMockStep_Commit {
    return {
        'statement' => 'COMMIT',
        'results'   => [ [] ],
    };
}

sub dbMockStep_Rollback {
    return {
        'statement' => 'ROLLBACK',
        'results'   => [ [] ],
    };
}
