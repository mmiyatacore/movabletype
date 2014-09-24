#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

BEGIN {
    $ENV{MT_CONFIG} = 'mysql-test.cfg';
}

BEGIN {
    use Test::More;
    eval { require Test::MockModule }
        or plan skip_all => 'Test::MockModule is not installed';
}

use lib qw(lib extlib t/lib);

eval(
    $ENV{SKIP_REINITIALIZE_DATABASE}
    ? "use MT::Test qw(:app);"
    : "use MT::Test qw(:app :db :data);"
);

use MT::App::DataAPI;
my $app    = MT::App::DataAPI->new;
my $author = MT->model('author')->load(1);
$author->email('melody@example.com');
$author->save;

my $mock_author = Test::MockModule->new('MT::Author');
$mock_author->mock( 'is_superuser', sub {0} );

my $mock_app_api = Test::MockModule->new('MT::App::DataAPI');
my $version;
$mock_app_api->mock( 'current_api_version',
    sub { $version = $_[1] if $_[1]; $version } );

my @suite = (
    {   path      => '/v1/users/me/sites',
        method    => 'GET',
        callbacks => [
            {   name  => 'data_api_pre_load_filtered_list.blog',
                count => 2,
            },
        ],
        result => sub {
            +{  'totalResults' => '2',
                'items'        => MT::DataAPI::Resource->from_object(
                    [   MT->model('blog')
                            ->load( { class => '*', }, { sort => 'id' } )
                    ]
                ),
            };
        },
    },
    {   path   => '/v1/users/4/sites',
        method => 'GET',
        result => sub {
            +{  'totalResults' => '0',
                'items'        => [],
            };
        },
    },
    {   path   => '/v1/users/9999/sites',
        method => 'GET',
        code   => 404,
    },
    {   path      => '/v1/sites/1',
        method    => 'GET',
        callbacks => [
            {   name =>
                    'MT::App::DataAPI::data_api_view_permission_filter.blog',
                count => 1,
            },
        ],
        result => sub {
            MT->model('blog')->load(1);
        },
    },
    {   path      => '/v1/sites/2',
        method    => 'GET',
        callbacks => [
            {   name =>
                    'MT::App::DataAPI::data_api_view_permission_filter.blog',
                count => 1,
            },
        ],
        result => sub {
            MT->model('blog')->load(2);
        },
    },

    # insert_new_website - irregular tests
    {   path     => '/v2/sites',
        method   => 'POST',
        code     => 400,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body, 'A resource "website" is required.' );
        },
    },
    {   path     => '/v2/sites',
        method   => 'POST',
        params   => { website => {}, },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "A parameter \"name\" is required.\n" );
        },
    },
    {   path   => '/v2/sites',
        method => 'POST',
        params => { website => { name => 'test-api-permission-website', }, },
        code   => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "A parameter \"url\" is required.\n" );
        },
    },
    {   path   => '/v2/sites',
        method => 'POST',
        params => {
            website => {
                name => 'test-api-permission-website',
                url  => 'http://narnia2.na/',
            },
        },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "A parameter \"sitePath\" is required.\n" );
        },
    },
    {   path   => '/v2/sites',
        method => 'POST',
        params => {
            website => {
                name     => 'test-api-permission-website',
                url      => 'http://narnia2.na/',
                sitePath => $FindBin::Bin,
            },
        },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "A parameter \"themeId\" is required.\n" );
        },
    },
    {   path   => '/v2/sites',
        method => 'POST',
        params => {
            website => {
                name     => 'test-api-permission-website',
                url      => 'http://narnia2.na/',
                sitePath => $FindBin::Bin,
                themeId  => 'dummy',
            },
        },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body, "Invalid theme_id: dummy\n" );
        },
    },
    {   path   => '/v2/sites',
        method => 'POST',
        params => {
            website => {
                name     => 'test-api-permission-website',
                url      => 'http://narnia2.na/',
                sitePath => 'relative/path',
                themeId  => 'classic_website',
            },
        },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "The website root directory must be absolute: relative\/path\n"
            );
        },
    },

    # insert_new_website - normal tests
    {   path   => '/v2/sites',
        method => 'POST',
        params => {
            website => {
                themeId      => 'classic_website',
                name         => 'test-api-permission-website',
                url          => 'http://narnia2.na/',
                sitePath     => $FindBin::Bin,
                serverOffset => '9',
                language     => 'ja',
            },
        },
        result => sub {
            MT->model('website')
                ->load( { name => 'test-api-permission-website' } );
        },
    },
);

my %callbacks = ();
my $mock_mt   = Test::MockModule->new('MT');
$mock_mt->mock(
    'run_callbacks',
    sub {
        my ( $app, $meth, @param ) = @_;
        $callbacks{$meth} ||= [];
        push @{ $callbacks{$meth} }, \@param;
        $mock_mt->original('run_callbacks')->(@_);
    }
);

my $format = MT::DataAPI::Format->find_format('json');

for my $data (@suite) {
    $data->{setup}->($data) if $data->{setup};

    my $path = $data->{path};
    $path
        =~ s/:(?:(\w+)_id)|:(\w+)/ref $data->{$1} ? $data->{$1}->id : $data->{$2}/ge;

    my $params
        = ref $data->{params} eq 'CODE'
        ? $data->{params}->($data)
        : $data->{params};

    my $note = $path;
    if ( lc $data->{method} eq 'get' && $data->{params} ) {
        $note .= '?'
            . join( '&',
            map { $_ . '=' . $data->{params}{$_} }
                keys %{ $data->{params} } );
    }
    $note .= ' ' . $data->{method};
    $note .= ' ' . $data->{note} if $data->{note};
    note($note);

    my $user = $data->{user} || $author;
    $user = $app->model('author')->load($user) unless ref $user;
    my $mock_app_api = Test::MockModule->new('MT::App::DataAPI');
    $mock_app_api->mock( 'authenticate', $user );

    %callbacks = ();
    _run_app(
        'MT::App::DataAPI',
        {   __path_info      => $path,
            __request_method => $data->{method},
            ( $data->{upload} ? ( __test_upload => $data->{upload} ) : () ),
            (   $params
                ? map {
                    $_ => ref $params->{$_}
                        ? MT::Util::to_json( $params->{$_} )
                        : $params->{$_};
                    }
                    keys %{$params}
                : ()
            ),
        }
    );
    my $out = delete $app->{__test_output};
    my ( $headers, $body ) = split /^\s*$/m, $out, 2;
    my %headers = map {
        my ( $k, $v ) = split /\s*:\s*/, $_, 2;
        $v =~ s/(\r\n|\r|\n)\z//;
        lc $k => $v
        }
        split /\n/, $headers;
    my $expected_status = $data->{code} || 200;
    is( $headers{status}, $expected_status, 'Status ' . $expected_status );
    if ( $data->{next_phase_url} ) {
        like(
            $headers{'x-mt-next-phase-url'},
            $data->{next_phase_url},
            'X-MT-Next-Phase-URL'
        );
    }

    foreach my $cb ( @{ $data->{callbacks} } ) {
        my $params_list = $callbacks{ $cb->{name} } || [];
        if ( my $params = $cb->{params} ) {
            for ( my $i = 0; $i < scalar(@$params); $i++ ) {
                is_deeply( $params_list->[$i], $cb->{params}[$i] );
            }
        }

        if ( my $c = $cb->{count} ) {
            is( @$params_list, $c,
                $cb->{name} . ' was called ' . $c . ' time(s)' );
        }
    }

    if ( my $expected_result = $data->{result} ) {
        $expected_result = $expected_result->( $data, $body )
            if ref $expected_result eq 'CODE';
        if ( UNIVERSAL::isa( $expected_result, 'MT::Object' ) ) {
            MT->instance->user($author);
            $expected_result = $format->{unserialize}->(
                $format->{serialize}->(
                    MT::DataAPI::Resource->from_object($expected_result)
                )
            );
        }

        my $result = $format->{unserialize}->($body);
        is_deeply( $result, $expected_result, 'result' );
    }

    if ( my $complete = $data->{complete} ) {
        $complete->( $data, $body );
    }
}

done_testing();

sub check_error_message {
    my ( $body, $error ) = @_;
    my $result = MT::Util::from_json($body);
    is( $result->{error}{message}, $error, 'Error message: ' . $error );
}
