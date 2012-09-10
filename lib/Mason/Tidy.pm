package Mason::Tidy;
use File::Slurp;
use HTML::PullParser;
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

# Implicitly empty tags (from emacs sgml-mode.el)
#
my @html_empty_tags = (
    "area",  "base",    "basefont", "br",   "col",   "frame", "hr", "img",
    "input", "isindex", "link",     "meta", "param", "wbr"
);
my %is_html_empty_tag = map { ( $_, 1 ) } @html_empty_tags;

# Tags for which end tag is optional (from emacs sgml-mode.el)
#
my @html_unclosed_tags = (
    "body", "colgroup", "dd", "dt",    "head", "html",  "li", "option",
    "p",    "tbody",    "td", "tfoot", "th",   "thead", "tr"
);
my %is_html_unclosed_tag = map { ( $_, 1 ) } @html_unclosed_tags;

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
        $add_element->( 'html_line', $line );
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

    # Create content from elements with perl lines as comments; indent html;
    # reassemble list of elements from tidied html blocks and replaced elements
    #
    my $untidied_html = join( "\n",
        map { $_->[0] eq 'html_line' ? $_->[1] : $self->replace_with_html_comment($_) } @elements );
    my $tidied_html = $self->htmltidy($untidied_html);
    @elements = ();
    foreach my $line ( split( /\n/, $tidied_html ) ) {
        if ( my $marker = $self->marker_in_line($line) ) {
            $add_element->( @{ $self->restore($marker) } );
        }
        else {
            $add_element->( 'html_line', $line );
        }
    }

    # Tidy Perl in <% %> tags
    #
    my $final = join( "\n", map { $_->[1] } @elements );

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

method replace_with_html_comment ($obj) {
    return "<!-- " . $self->replace_with_marker($obj) . " -->";
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

method jstidy ($source) {
}

method csstidy ($source) {
}

method htmltidy ($source) {
    my $p = HTML::PullParser->new(
        doc             => $source,
        start           => '"S", text, tagname',
        end             => '"E", text, tagname',
        default         => '"O", text',
        ignore_elements => [qw(script style)],
    ) || die "Can't open: $!";
    my $lineno = 0;
    my ( @delta_before_line, @delta_after_line );

    my @tagname_stack;
    my $new_line = 1;
    while ( my $token = $p->get_token ) {
        my ( $type, $text, $tagname ) = @$token;
        if ( $tagname eq 'script' ) {
            $script_mode = ( $type eq 'S' ? 1 : 0 );
        }
        if (   $type eq 'S'
            && $text !~ m{/>$}
            && !$is_html_empty_tag{$tagname} )
        {
            $delta_after_line[$lineno]++;
            if (   $is_html_unclosed_tag{$tagname}
                && @tagname_stack
                && $tagname_stack[-1] eq $tagname )
            {
                if ($new_line) {
                    $delta_before_line[$lineno]--;
                }
                else {
                    $delta_after_line[$lineno]--;
                }
            }
            else {
                push( @tagname_stack, $tagname );
            }
        }
        if ( $type eq 'E' ) {
            while ( my $popped_tagname = pop(@tagname_stack) ) {
                if ($new_line) {
                    $delta_before_line[$lineno]--;
                }
                else {
                    $delta_after_line[$lineno]--;
                }
                last if $popped_tagname eq $tagname;
            }
        }
        $lineno += ( $text =~ tr/\n// );
        $new_line = ( $text =~ /\n\s*$/m );
    }

    my $level  = 0;
    my $result = '';
    my @lines  = split( "\n", $source );

    for ( my $lineno = 0 ; $lineno < @lines ; $lineno++ ) {
        $level += ( $delta_before_line[$lineno] || 0 );
        $level = 0 if $level < 0;
        my $line = $lines[$lineno];
        $line =~ s/^\s+//m;
        $result .= scalar( '  ' x $level ) . $line . "\n";
        $level += ( $delta_after_line[$lineno] || 0 );
    }
    return $result;
}

sub trim {
    my $str = $_[0];
    for ($str) { s/^\s+//; s/\s+$// }
    return $str;
}

1;
