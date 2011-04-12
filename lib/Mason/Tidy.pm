package Mason::Tidy;
use File::Slurp;
use IO::Scalar;
use Method::Signatures::Simple;
use Moose;
use MooseX::HasDefaults::RO;
use MooseX::StrictConstructor;
use HTML::TreeBuilder;
use Mason::Tidy::Compilation::PlainText;

our $unique_string_count = 0;

# Passed attributes
has 'unique_string_prefix' => ( default => '__masontidy__' );

#
# BUILD
#

method tidy ($source) {
    foreach my $subclass qw(PlainText Substitution) {
        my $class = "Mason::Tidy::Compilation::$subclass";
        Class::MOP::load_class($class);
        my $c = $class->new( source => $source, tidy => $self );
        $c->transform;
        $source = $c->source;
    }
    return $source;
}

method unique_string () {
    return join( "_", $self->unique_string_prefix, $unique_string_count++ );
}

1;
