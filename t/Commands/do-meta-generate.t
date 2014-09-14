#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Copy;

use File::Temp;                      # Simple files for testing
use Test::More 'tests' => 3;     # Main test module; run this many tests
use Test::Exception;

BEGIN {
    *CORE::GLOBAL::readpipe = \&mock_readpipe; # Must be before use
    require Bio::SeqWare::Uploads::CgHub::Bam;
}

# Mock system calls.
my $mock_readpipe = { 'mock' => 0, 'ret' => undef , 'exit' => 0 };

sub mock_readpipe {
    my $var = shift;
    my $retVal;
    if ( $mock_readpipe->{'mock'} ) {
        $retVal = $mock_readpipe->{'ret'};
        $? = $mock_readpipe->{'exit'};
    }
    else {
        $retVal = CORE::readpipe($var);
    }
    return $retVal;
}

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 meta-generate);
my $SAMTOOLS_RETURN = 
"TTAGATAAAGGATACTG
AAAAGATAAGGATA
GCCTAAGCTAA
ATAGCTTCAGC
TAGGC
CAGCGGCAT
";

my $TEMP_DIR = File::Temp->newdir();  # Auto-delete self and contents when out of scope
my $DATA_DIR = File::Spec->catdir( "t", "Data", "Xml" );
my $GOOD_RUN_XML_FILE = File::Spec->catfile( $DATA_DIR, 'run.xml' );
my $GOOD_EXPERIMENT_XML_FILE = File::Spec->catfile( $DATA_DIR, 'experiment.xml' );
my $GOOD_ANALYSIS_XML_FILE = File::Spec->catfile( $DATA_DIR, 'analysis.xml' );
my $FAKE_BAM_FILE = File::Spec->catfile( $TEMP_DIR, 'fake.bam' );
copy($GOOD_RUN_XML_FILE, $FAKE_BAM_FILE) or die "Can't copy file for testing";

subtest( '_metaGenerate_getDataReadLength()' => \&test_metaGenerate_getDataReadLength );
subtest( '_metaGenerate_getDataReadCount()' => \&test_metaGenerate_getDataReadCount );
# subtest( '_metaGenerate_getData()' => \&test_metaGenerate_getData );
# subtest( '_metaGenerate_linkBam()' => \&test_metaGenerate_linkBam );
subtest( '_metaGenerate_makeDataDir()' => \&test_metaGenerate_makeDataDir );

sub test_metaGenerate_makeDataDir {
     plan( tests => 5 );

    {
        my $obj = makeBamForMetaGenerate();
        my $dataHR = { 'metadata_dir' => $TEMP_DIR, 'cghub_analysis_id' => $CLASS->getUuid() };
        my $want = File::Spec->catdir($dataHR->{'metadata_dir'}, $dataHR->{'cghub_analysis_id'});
        {
            ok( ! -d $want, "Directory doesn't pre-exist" );
        }
        my $got = $obj->_metaGenerate_makeDataDir( $dataHR );
        {
            is( $got, $want, "Created correct directory name" );
            ok( -d $got, "Directory now exists" );
        }
    }
    {
        my $message = "Fails if parent directory doesn't exist";
        my $obj = makeBamForMetaGenerate();
        my $dataHR = { 'cghub_analysis_id' => $TEMP_DIR, 'metadata_dir' => $CLASS->getUuid() };
        my $error1RES = "DirNotFoundException: Error looking up directory $dataHR->{'metadata_dir'}\. Error was:";
        my $errorRE = qr/^$error1RES\n\t/m;
        throws_ok( sub { $obj->_metaGenerate_makeDataDir( $dataHR ); }, $errorRE, $message );
    }
    {
        my $message = "Fails if parent directory not writeable";
        my $obj = makeBamForMetaGenerate();
        my $dataHR = { 'cghub_analysis_id' => $CLASS->getUuid(), 'metadata_dir' => File::Temp->newdir() };
        chmod( 0555, $dataHR->{'metadata_dir'} );
        my $want = File::Spec->catdir($dataHR->{'metadata_dir'}, $dataHR->{'cghub_analysis_id'});
        my $error1RES = 'CreateDirectoryException: Unable to create path "' . $want . '"\. Error was:';
        my $errorRE = qr/^$error1RES\n\t/m;
        throws_ok( sub { $obj->_metaGenerate_makeDataDir( $dataHR ); }, $errorRE, $message );
    }

}

sub test_metaGenerate_getDataReadLength {
    plan( tests => 6);

    # Good test
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "$SAMTOOLS_RETURN";

        {
            my $message = "Returns correct read length";
            my $want = 17; # Length of longest line in $SAMTOOLS_RETURN
            my $got = $obj->_metaGenerate_getDataReadLength( $anyRealFileName );
            is( $got, $want, $message);
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 1;
    }

    # Bad - No file path found
    {
        my $obj = makeBamForMetaGenerate();
        my $badFileName = $obj->getUuid() . ".bam";
        {
            my $message = "Error if provided filename not real.";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "BadParameterException: No such File:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $badFileName ); }, $matchRE, $message );
        }
    }

    # Bad - Undefined file path
    {
        my $obj = makeBamForMetaGenerate();
        my $badFileName = undef;
        {
            my $message = "Error if provided filename undefined";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "BadParameterException: Bam file name undefined\.";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $badFileName ); }, $matchRE, $message );
        }
    }

    # Bad - Samtools failed with error exit.
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'exit'} = 27;
        {
            my $message = "Error if Samtools failes with error exit";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "SamtoolsFailedException: Error getting reads\. Exit error code: 27\. Failure message was:";
            my $error3RES = "Original command was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n.*\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # Bad - Samtools produced no output.
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        {
            my $message = "Error if Samtools succceds but returns nothing";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "SamtoolsExecNoOutputException: Neither error nor result generated\. Strange\.";
            my $error3RES = "Original command was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n.*\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # Bad - Read length too short
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "AATTGG\n1234567890123456\n";

        {
            my $message = "Error if read length of returned string is <17.";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "SamtoolsShortReadException: Max read length to short, was: 16";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 1;
    }
}

sub test_metaGenerate_getDataReadCount {
    plan( tests => 5);

    # Lookup returns valid value - 2
    {
        my $experimentId = 5;
        my $readEnds = 2;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns valid value: 2";
            my $want = $readEnds;
            my $got = $obj->_metaGenerate_getDataReadCount( $experimentId );
            is( $got, $want, $message);
        }
    }

    {
        my $experimentId = 5;
        my $readEnds = 1;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns valid value: 1";
            my $want = $readEnds;
            my $got = $obj->_metaGenerate_getDataReadCount( $experimentId );
            is( $got, $want, $message);
        }
   }

   # Lookup returns invalid value - 0
   {
        my $experimentId = 5;
        my $readEnds = 0;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns invalid value: 0";
            my $errorRES1 = "DbReadCountException: Failed to retrieve the number of reads\. Error was:";
            my $errorRES2 = "DbDataError: Found $readEnds read ends, expected 1 or 2\.";
            my $matchRE = qr/^$errorRES1.*\n\t$errorRES2/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadCount( $experimentId ); }, $matchRE, $message);
        }
   }

   # Lookup returns invalid value - 3
   {
        my $experimentId = 5;
        my $readEnds = 3;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns invalid value: 3";
            my $errorRES1 = "DbReadCountException: Failed to retrieve the number of reads\. Error was:";
            my $errorRES2 = "DbDataError: Found $readEnds read ends, expected 1 or 2\.";
            my $matchRE = qr/^$errorRES1.*\n\t$errorRES2/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadCount( $experimentId ); }, $matchRE, $message);
        }
   }

   # Lookup returns invalid value - undef
   {
        my $experimentId = 5;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ [] ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns invalid value: undef";
            my $errorRES1 = "DbReadCountException: Failed to retrieve the number of reads\. Error was:";
            my $errorRES2 = "DbLookupError: Nothing retrieved from database\.";
            my $matchRE = qr/^$errorRES1.*\n\t$errorRES2/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadCount( $experimentId ); }, $matchRE, $message);
        }
   }
}

sub test_metaGenerate_getData {
    plan( tests => 1 );

    # Chosen to match analysis.xml data file
    my $upload_id       = 7851;
    my $fileTimestamp  = "2013-08-14 12:20:42.703867";
    my $sampleTcgaUuid = "66770b06-2cd6-4773-b8e8-5b38faa4f5a4";
    my $laneAccession  = 2090626;
    my $fileAccession  = 2149605;
    my $fileMd5sum     = "4181ac122b0a09f28cde79a9c3d5af39";
    my $filePath       = "$FAKE_BAM_FILE";   # Dummy file name, must actually exist, though.
    my $cghub_analysis_id     = "notReallyTheFastqUploadUuid";

    my $localFileLink  = "UNCID_2149605.66770b06-2cd6-4773-b8e8-5b38faa4f5a4.130702_UNC9-SN296_0379_AC25KWACXX_6_ACTTGA.fastq.tar.gz";
    my $fileBase       = "130702_UNC9-SN296_0379_AC25KWACXX_6_ACTTGA";
    my $uploadIdAlias  = "upload $upload_id";
    my $xmlTimestamp  = "2013-08-14T12:20:42.703867";

    # Additional for run.xml data file
    my $experimentAccession = 975937;
    my $sampleAccession    = 2090625;
    my $experimentId = -5;
    my $sampleId = -19;

    # Additional for experiment.xml
    my $instrumentModel = 'Illumina HiSeq 2000';
    my $experimentDescription = 'TCGA RNA-Seq Paired-End Experiment';
    my $readEnds       = 2;
    my $baseCoord      = 16;
    my $preservation   = '';

    my $expectData = {
        'program_version'    => $Bio::SeqWare::Uploads::CgHub::Fastq::VERSION,
        'sample_tcga_uuid'   => $sampleTcgaUuid,
        'lane_accession'     => $laneAccession,
        'file_md5sum'        => $fileMd5sum,
        'file_accession'     => $fileAccession,
        'upload_file_name'   => $localFileLink,
        'uploadIdAlias'      => $uploadIdAlias,
        'file_path_base'     => $fileBase,
        'analysis_date'      => $xmlTimestamp,
        'experiment_accession' => $experimentAccession,
        'sample_accession'   => $sampleAccession,
        'experiment_description' => $experimentDescription,
        'instrument_model'   => $instrumentModel,
        'read_ends'          => $readEnds,
        'library_layout'     => 'PAIRED',
        'base_coord'         => $baseCoord,
        'library_prep'       => 'Illumina TruSeq',
        'preservation'       => 'FROZEN',
    };

    my @dbSession = ({
        'statement'    => qr/SELECT.*/msi,
        'bound_params' => [ $upload_id ],
        'results'  => [
            [
                'file_timestamp',       'sample_tcga_uuid',  'lane_accession',
                'file_accession',       'file_md5sum',       'file_path',
                'upload_basedir', 'cghub_analysis_id', 'experiment_accession',
                'sample_accession',     'experiment_description', 'experiment_id',
                'instrument_model',     'sample_id', 'preservation',
            ], [
                $fileTimestamp,   $sampleTcgaUuid,     $laneAccession,
                $fileAccession,   $fileMd5sum,         $filePath,
                "$TEMP_DIR",      $cghub_analysis_id,         $experimentAccession,
                $sampleAccession, $experimentDescription, $experimentId,
                $instrumentModel, $sampleId, $preservation,
            ]
        ]
    },
    {
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
    });

    my $uploadHR = {'upload_id' => $upload_id};
    {

        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "Good run", @dbSession );
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "$SAMTOOLS_RETURN";
        my $got = $obj->_metaGenerate_getData( $uploadHR );
        my $want = $expectData;
        {
            is_deeply($got, $want, "Return value correct");
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 0;
    }

}

sub test_metaGenerate_linkBam {
    plan( tests => 1 );
    my $dataHR = {};

}

# Data providers

sub makeBamForMetaGenerate {

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
