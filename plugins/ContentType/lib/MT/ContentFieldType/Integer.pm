package MT::ContentFieldType::Integer;
use strict;
use warnings;

use MT::ContentField;

sub ss_validator {
    my ( $app, $field_id ) = @_;
    my $value = $app->param("content-field-${field_id}");
    return
        unless defined $value
        && $value ne '';    # Do not check empty value here.

    my $content_field = MT::ContentField->load($field_id);
    my $options       = $content_field->options;

    my $field_label = $options->{label};
    my $max_value   = $options->{max_value};
    my $min_value   = $options->{min_value};

    if ( $value !~ /^[+\-]?\d+$/ ) {
        return $app->errtrans( '"[_1]" field value must be integer.',
            $field_label );
    }

    if ( defined $max_value && $max_value ne '' ) {
        if ( $value > $max_value ) {
            return $app->errtrans(
                '"[_1]" field value must be less than or equal to [_2].',
                $field_label, $max_value );
        }
    }

    if ( defined $min_value && $min_value ne '' ) {
        if ( $value < $min_value ) {
            return $app->errtrans(
                '"[_1]" field value must be greater than or equal to [_2]',
                $field_label, $min_value );
        }
    }
}

1;
