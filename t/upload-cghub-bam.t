#!/usr/bin/env perl

use strict;
use warnings;
use Test::Script::Run;
use Test::More 'tests' => 1;     # Main test module; run this many subtests

run_ok( 'upload-cghub-bam', [], "Minimal run succeeds");