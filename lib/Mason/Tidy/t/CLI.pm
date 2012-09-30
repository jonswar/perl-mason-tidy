package Mason::Tidy::t::CLI;
use Capture::Tiny qw(capture capture_merged);
use File::Slurp;
use File::Temp qw(tempdir);
use Mason::Tidy;
use Mason::Tidy::App;
use IPC::System::Simple qw(capturex);
use IPC::Run3 qw(run3);
use Test::Class::Most parent => 'Test::Class';

my @std_argv = ( "--perltidy-argv='--noprofile'", "-m=2" );

sub test_cli : Tests {
    my ( $out, $err );

    my $tempdir = tempdir( 'name-XXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$tempdir/comp1.mc", "<%2+2%>" );
    write_file( "$tempdir/comp2.mc", "<%4+4%>" );
    write_file( "$tempdir/comp3.mc", "%if (foo){\n%bar\n%}\n" );

    my $cli = sub {
        my @argv = @_;
        ( $out, $err ) = capture {
            system( $^X, "bin/masontidy", @std_argv, @argv );
        };
    };

    $cli->( "-r", "$tempdir/comp1.mc", "$tempdir/comp2.mc" );
    is( $out,                           "",              "out empty" );
    is( $err,                           "",              "err empty" );
    is( read_file("$tempdir/comp1.mc"), "<% 2 + 2 %>\n", "comp1" );
    is( read_file("$tempdir/comp2.mc"), "<% 4 + 4 %>\n", "comp2" );

    write_file( "$tempdir/comp1.mc", "<%2+2%>" );
    $cli->("$tempdir/comp1.mc");
    is( $out,                           "<% 2 + 2 %>\n", "single file - out" );
    is( $err,                           "",              "single file - error" );
    is( read_file("$tempdir/comp1.mc"), "<%2+2%>",       "comp1" );

    $cli->("$tempdir/comp3.mc");
    is( $out, "% if (foo) {\n%     bar\n% }\n", "no options" );
    is( $err, "", "err empty" );
    $cli->( '--perltidy-line-argv="-i=2"', "$tempdir/comp3.mc" );
    is( $out, "% if (foo) {\n%   bar\n% }\n", "no options" );
    is( $err, "", "err empty" );

    ( $out, $err ) = capture {
        system( $^X, "bin/masontidy", "$tempdir/comp1.mc" );
    };
    like( $err, qr/mason-version required/ );

    ( $out, $err ) = capture {
        system( $^X, "bin/masontidy", "-m", "3", "$tempdir/comp1.mc" );
    };
    like( $err, qr/must be 1 or 2/ );

    $cli->( "-p", "$tempdir/comp1.mc" );
    like( $err, qr/pipe not compatible/ );

    $cli->();
    like( $err, qr/must pass either/ );

    $cli->( "$tempdir/comp1.mc", "$tempdir/comp2.mc" );
    like( $err, qr/must pass .* with multiple filenames/ );

    local $ENV{MASONTIDY_OPT} = "-p";
    my $in = "<%2+2%>\n<%4+4%>\n";
    run3( [ $^X, "bin/masontidy", @std_argv ], \$in, \$out, \$err );
    is( $err, "", "pipe - no error" );
    is( $out, "<% 2 + 2 %>\n<% 4 + 4 %>\n", "pipe - output" );
}

sub test_usage : Tests {
    my $out;

    return "author only" unless ( $ENV{AUTHOR_TESTING} );
    $out = capture_merged { system( $^X, "bin/masontidy", "-h" ) };
    like( $out, qr/Usage: masontidy/ );
}

1;
