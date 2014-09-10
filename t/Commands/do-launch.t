#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 5;     # Main test module; run this many tests
use Test::Exception;
use DBD::Mock;                   # Fake database results
use Test::MockModule;
use File::Spec;              # Generic file handling.
use Data::Dumper;

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my $SAMPLE_FILE_BAM = File::Spec->catfile( "t", "Data", "samplesToUpload.txt" );
my @DEF_CLI = (qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 launch ), $SAMPLE_FILE_BAM);

subtest( 'dbInsertUpload()'      => \&testDbInsertUpload );
subtest( 'dbInsertUploadFile()'  => \&testDbInsertUploadFile );
subtest( '_launch_prepareQueryInfo()'  => \&test_launch_prepareQueryInfo );
subtest( '_launch_prepareUploadInfo()' => \&test_launch_prepareUploadInfo );
subtest( 'do_launch()'                 => \&test_do_launch );

sub testDbInsertUpload{
    plan( tests => 3 );

    my $mockUploadId = 21;
    my $recHR = {
        sample_id => 19,
        target => 'CGHUB_BAM',
        status => 'launch_running',
        cghub_analysis_id => $CLASS->getUuid(),
        metadata_dir=>'/datastore/tcga/cghub/v2_uploads'
    };

    # valid run.
    {
        my @dbEvent = ({
            'statement'   => qr/INSERT INTO upload.*/msi,
            'bound_params' => [ $recHR->{sample_id},
                                $recHR->{target},
                                $recHR->{status},
                                $recHR->{cghub_analysis_id},
                                $recHR->{metadata_dir}],
            'results'  => [[ 'upload_id' ], [ $mockUploadId ]],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadRecord', @dbEvent );
        {
            my $message = "dbInsertUpload with good data works.";
            my $got = $obj->dbInsertUpload( $recHR );
            my $want = $mockUploadId;
            is( $got, $want, $message );
        }
    }

    # DB error.
    {
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql => "INSERT INTO upload ( sample_id, target, status, cghub_analysis_id, metadata_dir)
         VALUES ( ?, ?, ?, ?, ? )
         RETURNING upload_id",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Ooops.' ],
        };
        {
            my $message = "dbInsertUpload fails if db throws error.";
            my $error1RES = 'dbUploadInsertException: Insert of new upload record failed\. Error was:';
            my $error2RES = 'Ooops\.';
            my $errorRE = qr/$error1RES\n.*$error2RES/m;
            throws_ok( sub { $obj->dbInsertUpload( $recHR ); }, $errorRE, $message);
        }
    }

    # Bad returned results.
    {
        my @dbEvent = ({
            'statement'    => qr/INSERT INTO upload.*/msi,
            'bound_params' => [ $recHR->{sample_id},
                                $recHR->{target},
                                $recHR->{status},
                                $recHR->{cghub_analysis_id},
                                $recHR->{metadata_dir},
                              ],
            'results'  => [],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadRecord', @dbEvent );
        {
            my $message = "dbInsertUpload fails if db returns unexpected results.";
            my $error1RES = 'dbUploadInsertException: Insert of new upload record failed\. Error was:';
            my $error2RES = 'Id of the upload record inserted was not retrieved\.';
            my $errorRE = qr/$error1RES\n$error2RES/m;
            throws_ok( sub { $obj->dbInsertUpload( $recHR ); }, $errorRE, $message);
        }
    }
}

sub testDbInsertUploadFile{
     plan( tests => 3 );

    my $recHR = { upload_id => 21, file_id => 5 };

    # valid run.
    {
        my @dbEvent = ({
            'statement'   => qr/INSERT INTO upload_file.*/msi,
            'bound_params' => [ $recHR->{upload_id},
                                $recHR->{file_id},
                              ],
            'results'  => [[ 'file_id' ], [ $recHR->{file_id} ]],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadFileRecord', @dbEvent );
        {
            my $message = "dbInsertUploadFile with good data works.";
            my $got = $obj->dbInsertUploadFile( $recHR );
            my $want = $recHR->{file_id};
            is( $got, $want, $message );
        }
    }

    # DB error.
    {
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql =>  "INSERT INTO upload_file ( upload_id, file_id)
         VALUES ( ?, ? )
         RETURNING file_id",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Ooops.' ],
        };
        {
            my $message = "dbInsertUploadFile fails if db throws error.";
            my $error1RES = 'DbUploadFileInsertException: Insert of new upload_file record failed. Error was:';
            my $error2RES = 'Ooops\.';
            my $errorRE = qr/$error1RES\n.*$error2RES/m;
            throws_ok( sub { $obj->dbInsertUploadFile( $recHR ); }, $errorRE, $message);
        }
    }

    # Bad returned results.
    {
        my @dbEvent = ({
            'statement'    => qr/INSERT INTO upload_file.*/msi,
            'bound_params' => [ $recHR->{upload_id},
                                $recHR->{file_id},
                              ],
            'results'  => [],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadFileRecord', @dbEvent );
        {
            my $message = "dbInsertUploadFile fails if db returns unexpected results.";
            my $error1RES = 'DbUploadFileInsertException: Insert of new upload_file record failed\. Error was:';
            my $error2RES = 'Id of the file record linked to was not retrieved\.';
            my $errorRE = qr/$error1RES\n$error2RES/m;
            throws_ok( sub { $obj->dbInsertUploadFile( $recHR ); }, $errorRE, $message);
        }
    }
}

sub test_launch_prepareQueryInfo {
    plan( tests => 5 );

    my $obj = makeBamForlaunch();
    my $inputDAT = $obj->parseSampleFile();
    {
        my $message = "Line 1 of sample file converted correctly for Query.";
        my $got = $obj->_launch_prepareQueryInfo( $inputDAT->[0] );
        my $want = { 'sample' => 'TCGA1', 'flowcell' => 'UNC1', 'workflow_id' => 38,
            'lane' => 6, 'lane_index' => 5, 'barcode' => undef,
            'file_path' => undef, 'bam_file' => undef };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 2 of sample file converted correctly for Query, file_path";
        my $lookupHR = $inputDAT->[1];
        my %lookup = %$lookupHR;
        $lookup{'file_path'} = $lookup{'bam_file'};
        delete( $lookup{'bam_file'} );
        my $got = $obj->_launch_prepareQueryInfo( \%lookup );
        my $want = { 'sample' => 'TCGA2', 'flowcell' => 'UNC2', 'workflow_id' => 38,
            'lane' => 7, 'lane_index' => 6, 'barcode' => 'ATTCGG',
            'file_path' => undef };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 2 of sample file converted correctly for Query, no file";
        my $lookupHR = $inputDAT->[1];
        my %lookup = %$lookupHR;
        delete( $lookup{'bam_file'} );
        my $got = $obj->_launch_prepareQueryInfo( \%lookup );
        my $want = { 'sample' => 'TCGA2', 'flowcell' => 'UNC2', 'workflow_id' => 38,
            'lane' => 7, 'lane_index' => 6, 'barcode' => 'ATTCGG' };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 3 of sample file converted correctly for Query.";
        my $got = $obj->_launch_prepareQueryInfo( $inputDAT->[2] );
        my $want = { 'sample' => 'TCGA3', 'flowcell' => 'UNC3', 'workflow_id' => 38,
             'lane' => 8, 'lane_index' => 7, 'barcode' => 'ATTCGG',
             'file_path' => '/not/really', 'bam_file' => '/not/really' };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 4 of sample file converted correctly for Query.";
        my $got = $obj->_launch_prepareQueryInfo( $inputDAT->[3] );
        my $want = { 'sample' => 'TCGA4', 'flowcell' => 'UNC4', 'workflow_id' => 38,
             'lane' => 1, 'lane_index' => 0, 'barcode' => undef,
             'file_path' => '/old/fake', 'bam_file' => '/old/fake' };
        is_deeply( $got, $want, $message);
    }
}

sub test_launch_prepareUploadInfo {
    plan( tests => 2 );

    my $obj = makeBamForlaunch();
    my $inputHR = { 'sample_id' => 19, 'file_id' => 5,
             'lane_index' => 0, 'barcode' => 'ATGATG', 'file_path' => '/old/fake'  };
    my $forUploadHR = $obj->_launch_prepareUploadInfo( $inputHR );
    {
        my $message = "uuid added for upload";
        my $matchRE = qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/;
        like ($forUploadHR->{'cghub_analysis_id'}, $matchRE, $message);
    }
    {
        my $message = "Rest of upload record correct";
        my %got = %$forUploadHR;
        delete $got{'cghub_analysis_id'};
        my %want = ('sample_id' => 19, 'target' => 'CGHUB_BAM', 'file_id' => 5,
        'status' => 'launch_running', 'metadata_dir' => '/datastore/tcga/cghub/v2_uploads' );
        is_deeply( \%got, \%want, $message)
    }
}

sub test_do_launch {
    plan( tests => 3 );

    my $meta_type    = 'application/bam';
    my $type         = 'Mapsplice-sort';

    my $target            = 'CGHUB_BAM';
    my $status            = 'launch_running';
    my $metadata_dir      = '/datastore/tcga/cghub/v2_uploads';
    my $cghub_analysis_id = '00000000-0000-0000-0000-000000000000';

    my $dbEvent_dbGetBamFileInfo_Line1 = {
        'statement'    => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
        'bound_params' => [ $meta_type, $type, 'TCGA1', 'UNC1', 5, 38 ],
        'results'      => [
            [ 'sample', 'file_path', 'file_id', 'meta_type', 'flowcell', 'lane_index', 'barcode', 'type', 'sample_id', 'workflow_id' ],
            [ 'TCGA1',  undef, 5, $meta_type, 'UNC1', 5, undef, $type, 19, 38 ],
         ],
    };
    my $dbEvent_dbGetBamFileInfo_Line2 = {
        'statement'    => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
        'bound_params' => [ $meta_type, $type, 'TCGA2', 'UNC2', 6, 38, 'ATTCGG' ],
        'results'      => [
            [ 'sample', 'file_path', 'file_id', 'meta_type', 'flowcell', 'lane_index', 'barcode', 'type', 'sample_id', 'workflow_id' ],
            [ 'TCGA2',  undef, 6, $meta_type, 'UNC2', 6, 'ATTCGG', $type, 20, 38 ],
         ],
    };
    my $dbEvent_dbGetBamFileInfo_Line3 = {
        'statement'    => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
        'bound_params' => [ $meta_type, $type, 'TCGA3', 'UNC3', 7, 38, 'ATTCGG' ],
        'results'      => [
            [ 'sample', 'file_path', 'file_id', 'meta_type', 'flowcell', 'lane_index', 'barcode', 'type', 'sample_id', 'workflow_id' ],
            [ 'TCGA3',  '/not/really', 7, $meta_type, 'UNC3', 7, 'ATTCGG', $type, 21, 38 ],
         ],
    };
    my $dbEvent_dbGetBamFileInfo_Line4 = {
        'statement'    => qr/SELECT \* FROM vw_files WHERE meta_type = .*/msi,
        'bound_params' => [ $meta_type, $type, 'TCGA4', 'UNC4', 0, 38 ],
        'results'      => [
            [ 'sample', 'file_path', 'file_id', 'meta_type', 'flowcell', 'lane_index', 'barcode', 'type', 'sample_id', 'workflow_id' ],
            [ 'TCGA4',  '/old/fake', 8, $meta_type, 'UNC4', 0, undef, $type, 22, 38 ],
         ],
    };

    my $dbEvent_InsertUpload_Line1 = {
        'statement'    => qr/INSERT INTO upload.*/msi,
        'bound_params' => [ 19, $target, $status, $cghub_analysis_id, $metadata_dir],
        'results'      => [[ 'upload_id' ], [ 121 ]],
    };
    my $dbEvent_InsertUpload_Line2 = {
        'statement'    => qr/INSERT INTO upload.*/msi,
        'bound_params' => [ 20, $target, $status, $cghub_analysis_id, $metadata_dir],
        'results'      => [[ 'upload_id' ], [ 122 ]],
    };
    my $dbEvent_InsertUpload_Line3 = {
        'statement'    => qr/INSERT INTO upload.*/msi,
        'bound_params' => [ 21, $target, $status, $cghub_analysis_id, $metadata_dir],
        'results'      => [[ 'upload_id' ], [ 123 ]],
    };
    my $dbEvent_InsertUpload_Line4 = {
        'statement'    => qr/INSERT INTO upload.*/msi,
        'bound_params' => [ 22, $target, $status, $cghub_analysis_id, $metadata_dir],
        'results'      => [[ 'upload_id' ], [ 124 ]],
    };

    my $dbEvent_InsertUploadFile_Line1 = {
        'statement'    => qr/INSERT INTO upload_file.*/msi,
        'bound_params' => [ 121, 5 ],
        'results'  => [[ 'file_id' ], [ 5 ]],
    };
    my $dbEvent_InsertUploadFile_Line2 = {
        'statement'    => qr/INSERT INTO upload_file.*/msi,
        'bound_params' => [ 122, 6 ],
        'results'  => [[ 'file_id' ], [ 6 ]],
    };
    my $dbEvent_InsertUploadFile_Line3 = {
        'statement'    => qr/INSERT INTO upload_file.*/msi,
        'bound_params' => [ 123, 7 ],
        'results'  => [[ 'file_id' ], [ 7 ]],
    };
    my $dbEvent_InsertUploadFile_Line4 = {
        'statement'    => qr/INSERT INTO upload_file.*/msi,
        'bound_params' => [ 124, 8 ],
        'results'  => [[ 'file_id' ], [ 8 ]],
    };
    my $dbEvent_UpdateUpload_line1 = {
        'statement'   => qr/UPDATE upload SET status = .*/msi,
        'bound_params' => [ 'launch_done', 121 ],
        'results'  => [ [ 'rows' ], [] ],
    };
    my $dbEvent_UpdateUpload_line2 = {
        'statement'   => qr/UPDATE upload SET status = .*/msi,
        'bound_params' => [ 'launch_done', 122 ],
        'results'  => [ [ 'rows' ], [] ],
    };
    my $dbEvent_UpdateUpload_line3 = {
        'statement'   => qr/UPDATE upload SET status = .*/msi,
        'bound_params' => [ 'launch_done', 123 ],
        'results'  => [ [ 'rows' ], [] ],
    };
    my $dbEvent_UpdateUpload_line4 = {
        'statement'   => qr/UPDATE upload SET status = .*/msi,
        'bound_params' => [ 'launch_done', 124 ],
        'results'  => [ [ 'rows' ], [] ],
    };
    {
        my @dbLaunchEvents = (
            $dbEvent_dbGetBamFileInfo_Line1, $dbEvent_InsertUpload_Line1, $dbEvent_InsertUploadFile_Line1, $dbEvent_UpdateUpload_line1,
            $dbEvent_dbGetBamFileInfo_Line2, $dbEvent_InsertUpload_Line2, $dbEvent_InsertUploadFile_Line2, $dbEvent_UpdateUpload_line2,
            $dbEvent_dbGetBamFileInfo_Line3, $dbEvent_InsertUpload_Line3, $dbEvent_InsertUploadFile_Line3, $dbEvent_UpdateUpload_line3,
            $dbEvent_dbGetBamFileInfo_Line4, $dbEvent_InsertUpload_Line4, $dbEvent_InsertUploadFile_Line4, $dbEvent_UpdateUpload_line4
        );

        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('getUuid', sub { '00000000-0000-0000-0000-000000000000'; } );
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'do_launch', @dbLaunchEvents );
        {
            my $message = "do_launch with good data top down test.";
            ok( $obj->do_launch(), $message );
        }
    }
    {
        my $dbEvent_InsertUploadFileFail_Line1 = {
            'statement'    => qr/INSERT INTO upload_file.*/msi,
            'bound_params' => [ 121, 5 ],
            'results'  => [],
        };
        my $dbEvent_UpdateUploadFail_line1 = {
            'statement'   => qr/UPDATE upload SET status = .*/msi,
            'bound_params' => [ 'launch_failed_DbStatusUpdateException', 121 ],
            'results'  => [ [ 'rows' ], [] ],
        };

        my @dbLaunchFailEvent = (
            $dbEvent_dbGetBamFileInfo_Line1, $dbEvent_InsertUpload_Line1,
            $dbEvent_InsertUploadFileFail_Line1,
            $dbEvent_dbGetBamFileInfo_Line2, $dbEvent_InsertUpload_Line2, $dbEvent_InsertUploadFile_Line2, $dbEvent_UpdateUpload_line2,
            $dbEvent_dbGetBamFileInfo_Line3, $dbEvent_InsertUpload_Line3, $dbEvent_InsertUploadFile_Line3, $dbEvent_UpdateUpload_line3,
            $dbEvent_dbGetBamFileInfo_Line4, $dbEvent_InsertUpload_Line4, $dbEvent_InsertUploadFile_Line4, $dbEvent_UpdateUpload_line4
            
        );
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('getUuid', sub { '00000000-0000-0000-0000-000000000000'; } );
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'do_launchFail', @dbLaunchFailEvent );
        {
            my $message = "do_launch with fail triggering update to launch_failed";
            ok( $obj->do_launch(), $message );
        }

    }
    {
         my $message = "Hack to catch missing file error.";
         my $obj = makeBamForlaunch();
         delete $obj->{'sampleFile'};
         my $errorRE = qr/^Currently must specify the sample file to process as launch argument\./;
         throws_ok( sub { $obj->do_launch() }, $errorRE, $message );
    }
}

# Data providers

sub makeBamForlaunch {

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