#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 4;     # Main test module; run this many tests
use Test::Exception;
use DBD::Mock;                   # Fake database results

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy select);

{
    my $message = "no option, no argument";
    my $obj = makeBamForSelect();
    {
        $message .= " smoke test";
        ok( $obj->do_select() );
    }
}

# Test _select_insertUpload() valid run.
{
    my $recHR = { sample_id => 19, target => 'CGHUB_BAM',
     status => 'init-running', cghub_analysis_id => $CLASS->getUuid(),
     metadata_dir=>'/datastore/tcga/cghub/v2_uploads' };
    my $mockUploadId = 21;
    my @dbEvent = ({
        'statement'   => qr/INSERT INTO upload.*/msi,
        'bound_params' => [ $recHR->{sample_id}, $recHR->{target},
            $recHR->{status}, $recHR->{cghub_analysis_id}, $recHR->{metadata_dir}],
        'results'  => [[ 'upload_id' ], [ $mockUploadId ]],
    });
    my $obj = makeBamForSelect();
    $obj->{'dbh'}->{'mock_session'} =
        DBD::Mock::Session->new( 'newUploadRecord', @dbEvent );
    {
        my $message = "_select_insertUpload with good data works.";
        my $got = $obj->_select_insertUpload( $recHR );
        my $want = 1;
        is( $got, $want, $message );
    }
}

# Test error _select_insertUpload() DB error.
{
    my $recHR = { sample_id => 19, target => 'CGHUB_BAM',
     status => 'init-running', cghub_analysis_id => $CLASS->getUuid(),
     metadata_dir=>'/datastore/tcga/cghub/v2_uploads' };
    my $obj = makeBamForSelect();
    $obj->{'dbh'}->{mock_add_resultset} = {
        sql => "INSERT INTO upload ( sample_id, target, status, cghub_analysis_id, metadata_dir)
         VALUES ( ?, ?, ?, ?, ? )
         RETURNING upload_id",
        results => DBD::Mock->NULL_RESULTSET,
        failure => [ 5, 'Ooops.' ],
    };

    {
        my $message = "_select_insertUpload fails if db throws error.";
        my $errorRE = qr/^dbUploadInsertException: Insert of new upload record failed\. Error was:\n.*Ooops\./m;
        throws_ok( sub { $obj->_select_insertUpload( $recHR ); }, $errorRE, $message);
    }
}

# Test error _select_insertUpload() Bad returned results.
# Test _select_insertUpload() valid run.
{
    my $recHR = { sample_id => 19, target => 'CGHUB_BAM',
     status => 'init-running', cghub_analysis_id => $CLASS->getUuid(),
     metadata_dir=>'/datastore/tcga/cghub/v2_uploads' };
    my $mockUploadId = 21;
    my @dbEvent = ({
        'statement'   => qr/INSERT INTO upload.*/msi,
        'bound_params' => [ $recHR->{sample_id}, $recHR->{target},
            $recHR->{status}, $recHR->{cghub_analysis_id}, $recHR->{metadata_dir}],
        'results'  => [],
    });
    my $obj = makeBamForSelect();
    $obj->{'dbh'}->{'mock_session'} =
        DBD::Mock::Session->new( 'newUploadRecord', @dbEvent );
    {
        my $message = "_select_insertUpload fails if db returns unexpected results.";
        my $errorRE = qr/^dbUploadInsertException: Insert of new upload record failed\. Error was:\nId of the upload record inserted was not retrieved\./m;
        throws_ok( sub { $obj->_select_insertUpload( $recHR ); }, $errorRE, $message);
    }
}

sub makeBamForSelect {

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