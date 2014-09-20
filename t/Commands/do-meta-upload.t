#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Cwd;                         # get current working directory.

use Test::More 'tests' => 12;    # Main test module; run this many tests
use Test::Exception;             # Testing where code dies and errors
use Test::MockModule;            # Fake subroutine return values remotely


BEGIN {
    *CORE::GLOBAL::readpipe = \&mock_readpipe; # Must be before use
    require Bio::SeqWare::Uploads::CgHub::Bam;
}

# Mock system calls.
# Mock, set mock =1, unmock, set mock = 0.
# Mock one, set ret and exit
# Mock several, set session = [{ret=>, exit=>}, ...]
my $mock_readpipe = { 'mock' => 0, 'ret' => undef , 'exit' => 0, '_idx' => undef, 'argAR' => undef };

sub mock_readpipe {
    my $var = shift;
    my $retVal;
    if ( $mock_readpipe->{'mock'} ) {
        if (! $mock_readpipe->{'session'}) {
            $retVal = $mock_readpipe->{'ret'};
            if (defined $retVal && ref ($retVal) eq 'CODE') {
               if (defined $mock_readpipe->{'argAR'}) {
                   $retVal =  &$retVal(@{$mock_readpipe->{'argAR'}});
               }
               else {
                  $retVal =  &$retVal();
               }
            }
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
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy meta-upload);
my $UPLOAD_HR = {
    'upload_id' => -5,
    'metadata_dir' => "t",
    'cghub_analysis_id' => 'Data',
    'status' => 'meta-validate_done'
};
my $GOOD_META_UPLOAD = "Fake (GOOD) Submission Return\n"
                      . "Metadata Submission Succeeded.\n";

my $REPEAT_META_UPLOAD = "Fake (BAD) Submission Return\n"
                      . "Error    : You are attempting to submit an"
                      .  " analysis using a uuid that already exists within"
                      . " the system and is not in the upload or submitting state\n";

my $BAD_META_UPLOAD = "Fake (UNKNOWN) Submission Return\n"
                      . "Oops.\n";

# Good tests for _metaUpload
{
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $GOOD_META_UPLOAD;
        my $obj = makeBamForMetaUpload();
        {
            my $shows = "Success when returns valid message";
            my $got = $obj->_metaUpload( $UPLOAD_HR );
            my $want = 1;
            is( $got, $want, $shows);
        }
        $mock_readpipe->{'mock'} = 0;
    }
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $GOOD_META_UPLOAD;
        my $obj = makeBamForMetaUpload();
        {
            my $shows = "Directory doesn't change";
            my $want = getcwd();
            $obj->_metaUpload( $UPLOAD_HR );
            my $got = getcwd();
            is( $got, $want, $shows);
        }
        $mock_readpipe->{'mock'} = 0;
    }
}

# Errors from _metaUpload
{
    # $? not 0 (indicating failure) and text returned
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $BAD_META_UPLOAD;
        $mock_readpipe->{'exit'} = 99;
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Fails when update call errors, with error message";
            my $errorRES1 = "MetaUploadExec-99-WithOutputException: Exited with error value \"99\"\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_metaUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # $? not 0 (indicating failure) and no text returned
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'exit'} = 88;
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Fails when meta-upload call errors without error message";
            my $errorRES1 = "MetaUploadExec-88-NoOutputException: Exited with error value \"88\"\.";
            my $errorRES2 = "No output was generated\.";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_metaUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # $? not 0 (indicating failure) and "repeated upload" text returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $REPEAT_META_UPLOAD;
        $mock_readpipe->{'exit'} = 77;
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Fails when meta-upload call errors, with error message";
            my $errorRES1 = "MetaUploadExec-77-RepeatException: Already submitted. Exited with error value \"77\"\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_metaUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }
    # $? is 0 (indicating success) but no text returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'exit'} = 0;
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Fails when meta-upload call succeeds but without any response";
            my $errorRES1 = "MetaUploadExecNoOutputException: Neither error nor result generated\. Strange\.";
            my $errorRES2 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2/ms;
            throws_ok( sub {$obj->_metaUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }
    # $? is 0 (indicating success) but unexpected text is returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $BAD_META_UPLOAD;
        $mock_readpipe->{'exit'} = 0;
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Fails when meta-upload call succeeds but with incorrect response";
            my $errorRES1 = "MetaUploadExecUnexpectedOutput: Apparently failed to validate\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_metaUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }
    # $? is 0 (indicating success) but "repeated upload" text is returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $REPEAT_META_UPLOAD;
        $mock_readpipe->{'exit'} = 0;
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Fails when meta-upload call succeeds but returns REPEATED response";
            my $errorRES1 = "MetaUploadExecRepeatException: Already submitted\. Exited with success though\. Strange\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_metaUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

}

# Good run of do_meta_upload
{
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { return $UPLOAD_HR; } );
        $module->mock('dbSetDone', sub { 1 } );
        my $obj = makeBamForMetaUpload();

        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $GOOD_META_UPLOAD;
        {
            my $message = "Normal run of do_meta_upload.";
            my $got = $obj->do_meta_upload();
            my $want = 1;
            is($got, $want, $message);
        }
        $mock_readpipe->{'mock'} = 0;
    }
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { return; } );
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Normal run of do_meta_upload, Nothing to do.";
            my $got = $obj->do_meta_upload();
            my $want = 1;
            is($got, $want, $message);
        }
    }
}

# Bad run of do_meta_upload, mocking upload status changes, with uploadHR
{
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_metaUpload', sub { die "KaboomException: Bang.\n"; } );
        my $obj = makeBamForMetaUpload();
        my @dbEvents_ok = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ 'meta-validate_done' ],
                'results'  => [
                    ['upload_id', 'status', 'metadata_dir', 'cghub_analysis_id'],
                    [$UPLOAD_HR->{'upload_id'}, 'meta-validate_done', "t", 'Data'],
                ],
            },
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'meta-upload_running', $UPLOAD_HR->{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
            dbMockStep_Commit(),
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'meta-upload_failed_Kaboom', $UPLOAD_HR->{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
        );
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithReturn', @dbEvents_ok );
        {
            my $message = "Bad run of do_meta_upload with upload data.";
            my $errorRE = qr/^KaboomException: Bang\.\n$/;
            throws_ok(sub {$obj->do_meta_upload();}, $errorRE, $message );
        }
    }
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { die "KaboomException: Bang.\n"; } );
        my $obj = makeBamForMetaUpload();
        {
            my $message = "Bad run of do_meta_upload with no upload data.";
            my $errorRE = qr/^KaboomException: Bang\.\n\tAlso: upload data not available\n/;
            throws_ok(sub {$obj->do_meta_upload();}, $errorRE, $message );
        }
    }
}

sub makeBamForMetaUpload {

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