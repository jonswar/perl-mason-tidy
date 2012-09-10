package Mason::Tidy;
use File::Slurp;
use IO::Scalar;
use IPC::Run;
use Method::Signatures::Simple;
use Perl::Tidy qw();
use strict;
use warnings;

my $marker_count  = 0;
my $marker_prefix = '__masontidy__';
my $open_block_regex =
  '<%(after|args|around|augment|before|class|doc|filter|flags|init|method|override|perl|shared|text)(\s+\w+)?>';

method tidy ($source) {
    return $self->tidy_method($source);
}

method tidy_method ($source) {
    my @lines       = split( /\n/, $source );
    my @elements    = ();
    my $add_element = sub { push( @elements, [@_] ) };

    my $last_line = scalar(@lines) - 1;
    for ( my $cur_line = 0 ; $cur_line <= $last_line ; $cur_line++ ) {
        my $line = $lines[$cur_line];
        if ( $line =~ /^%%/ ) { $add_element->( 'ignore_line', $line ); next }
        if ( $line =~ /^%/ )  { $add_element->( 'perl_line',   $line ); next }
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
        map { $_->[0] eq 'perl_line' ? substr( $_->[1], 2 ) : $self->replace_with_perl_comment($_) }
          @elements
    );
    $self->perltidy(
        source      => \$untidied_perl,
        destination => \my $tidied_perl,
        argv        => '-noll -fnl -nbbc -i=2'
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
    $final =~ s/<%\s+(.*?)\s+%>/'<% ' . $self->tidy_subst_expr($1) . ' %>'/ge;

    return $final;
}

method tidy_subst_expr ($expr) {
    $self->perltidy( source => \$expr, destination => \my $tidied_expr, argv => '-noll' );
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
    if ( $block_type =~ /^(class|init|perl)$/ ) {
        $self->perltidy(
            source      => \$block_contents,
            destination => \my $tidied_block_contents,
            argv        => '-noll'
        );
        $block_contents = trim($tidied_block_contents);
    }
    elsif ( $block_type =~ /^(after|augment|around|before|filter|method|override)/ ) {
        $block_contents = $self->tidy_method($block_contents);
    }
    $block_contents =~ s/^(?!%)/  /mg;
    return $block_contents;
}

method replace_with_perl_comment ($obj) {
    return "# " . $self->replace_with_marker($obj);
}

method replace_with_marker ($obj) {
    my $marker = join( "_", $marker_prefix, $marker_count++ );
    $self->{markers}->{$marker} = $obj;
    return $marker;
}

method marker_in_line ($line) {
    if ( my ($marker) = ( $line =~ /(${marker_prefix}_\d+)/ ) ) {
        return $marker;
    }
    return undef;
}

method restore ($marker) {
    return $self->{markers}->{$marker};
}

method perltidy () {
    Perl::Tidy::perltidy(
        prefilter  => \&perltidy_prefilter,
        postfilter => \&perltidy_postfilter,
        @_
    );
}

sub perltidy_prefilter {
    my ($buf) = @_;
    $buf =~ s/\$\./\$__SELF__->/g;
    return $buf;
}

sub perltidy_postfilter {
    my ($buf) = @_;
    $buf =~ s/\$__SELF__->/\$\./g;
    $buf =~ s/ *\{ *\{/ \{\{/g;
    $buf =~ s/ *\} *\}/\}\}/g;
    return $buf;
}

sub trim {
    my $str = $_[0];
    for ($str) { s/^\s+//; s/\s+$// }
    return $str;
}

1;
