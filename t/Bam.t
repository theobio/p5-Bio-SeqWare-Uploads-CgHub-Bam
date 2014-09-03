#! /usr/bin/env perl

use Test::More 'tests' => 2;     # Main test module; run this many subtests
use Scalar::Util qw( blessed );  # Get class of objects

use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

# Run these tests
subtest( 'new()' => \&testNew );
subtest( 'run()' => \&testRun );

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