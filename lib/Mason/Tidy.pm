package Mason::Tidy;
use File::Slurp;
use IO::Scalar;
use IPC::Run;
use Method::Signatures::Simple;
use Moo;
use Perl::Tidy qw();
use strict;
use warnings;

my $marker_count = 0;

# Public
has 'indent_perl_block'   => ( is => 'ro', default => sub { 2 } );
has 'perltidy_argv'       => ( is => 'ro', default => sub { '' } );
has 'perltidy_block_argv' => ( is => 'ro', default => sub { '' } );
has 'perltidy_line_argv'  => ( is => 'ro', default => sub { '-i=2' } );
has 'perltidy_tag_argv'   => ( is => 'ro', default => sub { '' } );

# Private
has '_is_mixed_block'   => ( is => 'lazy' );
has '_is_perl_block'    => ( is => 'lazy' );
has '_marker_prefix'    => ( is => 'ro', default => sub { '__masontidy__' } );
has '_open_block_regex' => ( is => 'lazy' );
has '_subst_tag_regex'  => ( is => 'lazy' );

method _build__is_mixed_block () {
    return { map { ( $_, 1 ) } $self->mixed_block_names };
}

method _build__is_perl_block () {
    return { map { ( $_, 1 ) } $self->perl_block_names };
}

method _build__open_block_regex () {
    my $re = '<%(' . join( '|', $self->block_names ) . ')(\s+\w+)?>';
    return qr/$re/;
}

method _build__subst_tag_regex () {
    my $re = '<%(?!' . join( '|', $self->block_names ) . ')(.*?)%>';
    return qr/$re/;
}

method block_names () {
    return
      qw(after args around attr augment before class cleanup def doc filter flags init method once override perl shared text);
}

method perl_block_names () {
    return qw(class init once perl shared);
}

method mixed_block_names () {
    return qw(after augment around before def filter method override);
}

method tidy ($source) {
    return $self->tidy_method($source);
}

method tidy_method ($source) {
    my @lines            = split( /\n/, $source );
    my @elements         = ();
    my $add_element      = sub { push( @elements, [@_] ) };
    my $open_block_regex = $self->_open_block_regex;

    my $last_line = scalar(@lines) - 1;
    for ( my $cur_line = 0 ; $cur_line <= $last_line ; $cur_line++ ) {
        my $line = $lines[$cur_line];
        if ( $line =~ /^%/ ) { $add_element->( 'perl_line', $line ); next }
        if ( my ($block_type) = ( $line =~ $open_block_regex ) ) {
            my $end_line = $self->capture_block( \@lines, $block_type, $cur_line + 1, $last_line );
            my $block_contents = join( "\n", @lines[ $cur_line + 1 .. $end_line - 1 ] );
            $block_contents = join( "\n",
                $lines[$cur_line], $self->handle_block( $block_type, $block_contents ),
                $lines[$end_line] );
            $add_element->( 'block', $block_contents );
            $cur_line = $end_line;
            next;
        }
        $add_element->( 'text_line', $line );
    }

    # Create content from elements with non-perl lines as comments; perltidy;
    # reassemble list of elements from tidied perl blocks and replaced elements
    #
    my $untidied_perl = join(
        "\n",
        map {
            $_->[0] eq 'perl_line'
              ? trim( substr( $_->[1], 1 ) )
              : $self->replace_with_perl_comment($_)
        } @elements
    );
    $self->perltidy(
        source      => \$untidied_perl,
        destination => \my $tidied_perl,
        argv        => $self->perltidy_line_argv . " -fnl -fbl",
    );

    @elements = ();
    foreach my $line ( split( /\n/, $tidied_perl ) ) {
        if ( my $marker = $self->marker_in_line($line) ) {
            $add_element->( @{ $self->restore($marker) } );
        }
        else {
            $add_element->( 'perl_line', "% " . $line );
        }
    }
    my $final = join( "\n", map { $_->[1] } @elements );

    # Tidy Perl in <% %> tags
    #
    my $subst_tag_regex = $self->_subst_tag_regex;
    $final =~ s/$subst_tag_regex/'<% ' . $self->tidy_subst_expr($1) . ' %>'/ge;

    return $final;
}

method tidy_subst_expr ($expr) {
    $self->perltidy(
        source      => \$expr,
        destination => \my $tidied_expr,
        argv        => $self->perltidy_tag_argv,
    );
    return trim($tidied_expr);
}

method capture_block ($lines, $block_type, $cur_line, $last_line) {
    foreach my $this_line ( $cur_line .. $last_line ) {
        if ( $lines->[$this_line] =~ m{</%$block_type>} ) {
            return $this_line;
        }
    }
    die "could not find matching </%$block_type> after line $cur_line";
}

method handle_block ($block_type, $block_contents) {
    if ( $self->_is_perl_block->{$block_type} ) {
        $block_contents = trim_lines($block_contents);
        $self->perltidy(
            source      => \$block_contents,
            destination => \my $tidied_block_contents,
            argv        => $self->perltidy_block_argv
        );
        $block_contents = trim($tidied_block_contents);
        my $spacer = scalar( ' ' x $self->indent_perl_block );
        $block_contents =~ s/^/$spacer/mg;
    }
    elsif ( $self->_is_mixed_block->{$block_type} ) {
        $block_contents = $self->tidy_method($block_contents);
    }
    return $block_contents;
}

method replace_with_perl_comment ($obj) {
    return "# " . $self->replace_with_marker($obj);
}

method replace_with_marker ($obj) {
    my $marker = join( "_", $self->_marker_prefix, $marker_count++ );
    $self->{markers}->{$marker} = $obj;
    return $marker;
}

method marker_in_line ($line) {
    my $marker_prefix = $self->_marker_prefix;
    if ( my ($marker) = ( $line =~ /(${marker_prefix}_\d+)/ ) ) {
        return $marker;
    }
    return undef;
}

method restore ($marker) {
    return $self->{markers}->{$marker};
}

method perltidy (%params) {
    $params{argv} .= ' ' . $self->perltidy_argv;
    Perl::Tidy::perltidy(
        prefilter  => \&perltidy_prefilter,
        postfilter => \&perltidy_postfilter,
        %params
    );
}

func perltidy_prefilter ($buf) {
    $buf =~ s/\$\./\$__SELF__->/g;
    return $buf;
}

func perltidy_postfilter ($buf) {
    $buf =~ s/\$__SELF__->/\$\./g;
    $buf =~ s/ *\{ *\{/ \{\{/g;
    $buf =~ s/ *\} *\}/\}\}/g;
    return $buf;
}

func trim ($str) {
    for ($str) { s/^\s+//; s/\s+$// }
    return $str;
}

func trim_lines ($str) {
    for ($str) { s/^\s+//m; s/\s+$//m }
    return $str;
}

1;

__END__

=pod

=head1 NAME

Mason::Tidy - Engine for masontidy

=head1 SYNOPSIS

    use Mason::Tidy;

    my $mc = Mason::Tidy->new();
    my $dest = $mc->tidy($source);

=head1 DESCRIPTION

This is the engine used by L<masontidy|masontidy> - read that first to get an
overview.

You can call this API from your own program instead of executing C<masontidy>.

=head1 CONSTRUCTOR PARAMETERS

=over

=item indent_perl_block

=item perltidy_argv

=item perltidy_block_argv

=item perltidy_line_argv

=item perltidy_subst_argv

These options are the same as the equivalent C<masontidy> command-line options,
replacing dashes with underscore (e.g. the C<indent-per-block> option becomes
C<indent_perl_block> here).

=back

=head1 METHODS

=over

=item tidy ($source)

Tidy component source I<$source> and return the result.

=back

=cut
