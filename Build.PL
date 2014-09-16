use 5.014;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Bio::SeqWare::Uploads::CgHub::Bam',
    license             => 'gpl',
    dist_author         => q{Stuart R. Jefferys <srjefferys (at) gmail (dot) com>},
    dist_version_from   => 'lib/Bio/SeqWare/Uploads/CgHub/Bam.pm',
    recursive_test_files => 1,
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::Script::Run' => 0,
        'Test::Exception'  => 0,
        'Test::Output'     => 0,
        'Test::MockModule' => 0,
        'DBD::Mock'        => 0,
        'Test::MockObject::Extends' => 0,
    },
    requires => {
        'perl'          => '5.014',
        'Bio::SeqWare::Db::Connection'=> '0.000004', # Using corrected compatible object feature.
        'Bio::SeqWare::Config'        => '0.000003', # Added needed keys.
        'DBD::Pg'       => 0,
        'DBI'           => 0,
        'Template'      => 0,
        'File::HomeDir' => 0,
        'File::Share'   => 0,
        'Data::GUID'    => 0,
    },
    add_to_cleanup     => [ 'p5-Bio-SeqWare-Uploads-CgHub-Bam-*' ],
    create_makefile_pl => 'traditional',
    share_dir => 'share',
);

$builder->create_build_script();
