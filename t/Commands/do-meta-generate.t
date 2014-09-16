#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Copy;

use File::Temp;                      # Simple files for testing
use Test::More 'tests' => 5;     # Main test module; run this many tests
use Test::Exception;
use Test::File::Contents;

BEGIN {
    *CORE::GLOBAL::readpipe = \&mock_readpipe; # Must be before use
    require Bio::SeqWare::Uploads::CgHub::Bam;
}

# Mock system calls.
# Mock, set mock =1, unmock, set mock = 0.
# Mock one, set ret and exit
# Mock several, set session = [{ret=>, exit=>}, ...]
my $mock_readpipe = { 'mock' => 0, 'ret' => undef , 'exit' => 0, '_idx' => undef };

sub mock_readpipe {
    my $var = shift;
    my $retVal;
    if ( $mock_readpipe->{'mock'} ) {
        if (! $mock_readpipe->{'session'}) {
            $retVal = $mock_readpipe->{'ret'};
            $? = $mock_readpipe->{'exit'};
        }
        else {
            my @session = @{$mock_readpipe->{'session'}};
            my $idx = $mock_readpipe->{'_idx'};
            if (! defined $idx) {
                $idx = 0;
            }
            if ($idx >= @session) {
                die "Mock::ReadPipeException: Not enough session elements defined.\n";
            }
            $retVal = $mock_readpipe->{'session'}->[$idx]->{'ret'};
            $? = $mock_readpipe->{'session'}->[$idx]->{'exit'};
            $mock_readpipe->{'_idx'} += 1;
        }
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

subtest( '_metaGenerate_getDataReadLength()' => \&test_getDataReadLength );
subtest( '_metaGenerate_getDataReadCount()' => \&test_getDataReadCount );
subtest( '_metaGenerate_linkBam()' => \&test_linkBam );
subtest( '_metaGenerate_makeDataDir()' => \&test_makeDataDir );
# subtest( '_metaGenerate_getData()' => \&test_getData );
subtest( '_metaGenerate_makeFileFromTemplate()' => \&test_makeFileFromTemplate );

sub test_makeDataDir {
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

sub test_linkBam {
    plan( tests => 6 );

    my $obj = makeBamForMetaGenerate();
    {
        my $dataHR = {
            'file_path' => $FAKE_BAM_FILE, 'dataDir' => $TEMP_DIR,
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        my $filename = 'fake.bam';
        my $wantLinkName = 'UNCID_111111.' . $dataHR->{'sample_tcga_uuid'} . ".$filename";
        my $wantLinkPath = File::Spec->catfile($dataHR->{'dataDir'}, $wantLinkName);
        {
            ok(! -l $wantLinkPath, "Link doesn't pre-exist");
        }
        {
            my $message = 'Link file name is returned correctly';
            my $want = $wantLinkName;
            my $got = $obj->_metaGenerate_linkBam( $dataHR );
            is($got, $want, $message);
        }
        {
            ok(-l $wantLinkPath, "Link is created");
            unlink( $wantLinkPath ) or die ("Deleting link $wantLinkPath failed. $!");
        }
    }
    {
        my $dataHR = {
            'file_path' => $CLASS->getUuid(), 'dataDir' => $TEMP_DIR,
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        {
            my $message = 'Error if file linked to does not exist';
            my $error1RES = 'FileNotFoundException: Error looking up file ' . $dataHR->{'file_path'} . '\. Error was:';
            my $errorRE = qr/^$error1RES\n\t/;
            throws_ok( sub { $obj->_metaGenerate_linkBam( $dataHR ); }, $errorRE, $message);
        }
    }
    {
        my $dataHR = {
            'file_path' => $FAKE_BAM_FILE, 'dataDir' => $CLASS->getUuid(),
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        {
            my $message = 'Error if dir link put in does not exist';
            my $error1RES = 'DirNotFoundException: Error looking up directory ' . $dataHR->{'dataDir'} . '\. Error was:';
            my $errorRE = qr/^$error1RES\n\t/;
            throws_ok( sub { $obj->_metaGenerate_linkBam( $dataHR ); }, $errorRE, $message);
        }
    }
    {
        my $dataHR = {
            'file_path' => $FAKE_BAM_FILE, 'dataDir' => File::Temp->newdir(),
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        my $filename = 'fake.bam';
        my $wantLinkName = 'UNCID_111111.' . $dataHR->{'sample_tcga_uuid'} . ".$filename";
        my $wantLinkPath = File::Spec->catfile($dataHR->{'dataDir'}, $wantLinkName);
        {
            my $message = 'Error if creating link fails';
            chmod( 0555, $dataHR->{'dataDir'} );
            my $error1RES = 'CreateLinkException: Could not create symlink:';
            my $error2RES = 'Link: "' . $wantLinkPath . '"';
            my $error3RES = 'Pointing to: "' . $dataHR->{'file_path'} . '"\. Error was:';
            my $errorRE = qr/^$error1RES\n\t$error2RES\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_linkBam( $dataHR ); }, $errorRE, $message);
        }
    }
}

sub test_getDataReadLength {
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
            my $error2RES = "FileNotFoundException: Error looking up file $badFileName\. Error was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n\t/;
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
            my $error2RES = "ValueNotDefinedException: Expected a defined value\.";
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

sub test_getDataReadCount {
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

sub test_getData {
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
        $mock_readpipe->{'session'} = [
            { 'ret' => "$SAMTOOLS_RETURN", 'exit' => 0 },
        ];
        my $got = $obj->_metaGenerate_getData( $uploadHR );
        my $want = $expectData;
        {
            is_deeply($got, $want, "Return value correct");
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 0;
    }

}

sub test_makeFileFromTemplate {
    plan( tests => 15);

    my $uploadHR = {
        'upload_id'         => 23985,
        'sample_id'         => 18254,
        'target'            => 'CGHUB',
        'status'            => 'CGHUB_Complete',
        'cghub_analysis_id' => '41a12166-ec7e-447b-94b2-9f3dd96401ca',
        'tstmp'             => '2014-08-13 10:06:46.949567',
        'metadata_dir'      => 'datastore/tcga/cghub/v2_uploads',
        'external_status'   => 'live',
    };

    # Data (as would be needed for the target xml files.)
    my $linkName = 'UNCID_2462755.23b47813-7a77-44ca-b650-31a319c1f497.sorted_genome_alignments.bam';

    my $runDataHR = {
        'lane_accession'       => 2449977,
        'experiment_accession' => 975937,
        'sample_accession'     => 2449976,
    };

    my $analysisDataHR = {
        'uploadIdAlias'      => 2574890,
        'analysisDate'       => '2014-05-19T15:47:52.663',
        'workflow_accession' => 1015700,
        'tcga_uuid'          => '23b47813-7a77-44ca-b650-31a319c1f497',
        'lane_accession'     => 2449977,
        'readGroup'          => '140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC',
        'fileNoExtension'    => 'sorted_genome_alignments',
        'workflow_name'      => 'MapspliceRSEM',
        'workflow_version'   => '0.7.4',
        'workflow_algorithm' => 'samtools-sort-genome',
        'file_accession'     => 2462755,
        'file_md5sum'        => '04f5a22164bb399f61a2caee8ecb048b',
        'uncFileSampleName'  => 'UNCID_2462755.23b47813-7a77-44ca-b650-31a319c1f497.sorted_genome_alignments.bam',
    };

        my $experimentDataHR = {
            'experiment_accession'   => 975937,
            'sample_accession'       => 2449976,
            'experiment_description' => 'TCGA RNA-Seq Paired-End Experiment',
            'tcga_uuid'              => '23b47813-7a77-44ca-b650-31a319c1f497',
            'libraryPrep'            => 'Illumina TruSeq',
            'LibraryLayout'          => "PAIRED",
            'readEnds'               => 2,
            'baseCoord'              => 49,
            'instrument_model'       => 'Illumina HiSeq 2000',
            'preservation'           => 'FROZEN',
        };

    my $obj = makeBamForMetaGenerate();
    # run.xml
    {

        my $sampleFileName = File::Spec->catfile( "t", "Data", "Xml", "run.xml" );
        my $outFileName = File::Spec->catfile( "$TEMP_DIR", "run.xml" );
        my $templateFileName = File::Spec->catfile($obj->{'templateBaseDir'}, $obj->{'xmlSchema'}, "run.xml.template" );

        # Files for use by test are available
        {
            ok( (-f $templateFileName), "Can find run.xml.template");
            ok( (-f $sampleFileName), "Can find run.xml example");
        }

        # Absolute paths
        {
            my $runXml = $obj->_metaGenerate_makeFileFromTemplate( $runDataHR, $outFileName, $templateFileName );
            {
                is ( $runXml, $outFileName, "Appeared to create run.xml file");
                ok( (-f $runXml),   "Can find run.xml file");
                files_eq_or_diff( $runXml, $sampleFileName, "run.xml file generated correctly." );
            }
        }
    }

    # analysis.xml
    {

        my $sampleFileName = File::Spec->catfile( "t", "Data", "Xml", "analysis.xml" );
        my $outFileName = File::Spec->catfile( "$TEMP_DIR", "analysis.xml" );
        my $templateFileName = File::Spec->catfile($obj->{'templateBaseDir'}, $obj->{'xmlSchema'}, "analysis.xml.template" );

        # Files for use by test are available
        {
            ok( (-f $templateFileName), "Can find analysis.xml.template");
            ok( (-f $sampleFileName), "Can find analysis.xml example");
        }

        # Absolute paths
        {
            my $analysisXml = $obj->_metaGenerate_makeFileFromTemplate( $analysisDataHR, $outFileName, $templateFileName );
            {
                is ( $analysisXml, $outFileName, "Appeared to create analysis.xml file");
                ok( (-f $analysisXml),   "Can find analysis.xml file");
                files_eq_or_diff( $analysisXml, $sampleFileName, "analysis.xml file generated correctly." );
            }
        }
    }

    # experment.xml
    {

        my $sampleFileName = File::Spec->catfile( "t", "Data", "Xml", "experiment.xml" );
        my $outFileName = File::Spec->catfile( "$TEMP_DIR", "experiment.xml" );
        my $templateFileName = File::Spec->catfile($obj->{'templateBaseDir'}, $obj->{'xmlSchema'}, "experiment.xml.template" );

        # Files for use by test are available
        {
            ok( (-f $templateFileName), "Can find experiment.xml.template");
            ok( (-f $sampleFileName), "Can find experiment.xml example");
        }

        # Absolute paths
        {
            my $experimentXml = $obj->_metaGenerate_makeFileFromTemplate( $experimentDataHR, $outFileName, $templateFileName );
            {
                is ( $experimentXml, $outFileName, "Appeared to create experiment.xml file");
                ok( (-f $experimentXml),   "Can find experiment.xml file");
                files_eq_or_diff( $experimentXml, $sampleFileName, "experiment.xml file generated correctly." );
            }
        }
    }

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
