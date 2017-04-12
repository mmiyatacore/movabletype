# Movable Type (r) (C) 2007-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

package ContentType::Tags;

use strict;

use JSON;

sub _hdlr_contents {
    my ( $ctx, $args, $cond ) = @_;

    my $terms;
    my $type    = $args->{type};
    my $name    = $args->{name};
    my $blog_id = $args->{blog_id};
    if ($type) {
        $terms = { unique_key => $type };
    }
    elsif ( $name && $blog_id ) {
        $terms = {
            blog_id => $blog_id,
            name    => $name,
        };
    }
    else {
        return $ctx->error(
            MT->translate(
                '\'type\' or "\'name\' and \'blog_id\'" is required.')
        );
    }
    my ($content_type) = MT::ContentType->load($terms)
        or return $ctx->error( MT->translate('Content Type was not found.') );

    my $parent      = $ctx->stash('content_type');
    my $parent_data = $ctx->stash('content');
    my @data_ids;
    my $e_hash = {};

    if ($parent) {
        my $f_json = $parent->fields;
        my $fields = $f_json ? JSON::decode_json($f_json) : [];

        my $match = 0;
        foreach my $f (@$fields) {
            my $field_obj = MT::ContentField->load( $f->{id} );
            if (   $f->{type} eq 'content_type'
                && $field_obj->related_content_type_id == $content_type->id )
            {
                $match++;
                my $json     = $parent_data->data;
                my $data     = $json ? JSON::decode_json($json) : [];
                my $data_ids = $data->{ $f->{id} };
                @data_ids = split ',', $data_ids;
            }
        }

        return $ctx->error( MT->translate('Content Type was not found.') )
            unless $match;
    }

    my @contents
        = MT::ContentData->load( { content_type_id => $content_type->id } );

    my $i       = 0;
    my $res     = '';
    my $tok     = $ctx->stash('tokens');
    my $builder = $ctx->stash('builder');
    my $vars    = $ctx->{__stash}{vars} ||= {};
    for my $content_data (@contents) {
        next if $parent && !grep { $content_data->id == $_ } @data_ids;

        local $vars->{__first__}       = !$i;
        local $vars->{__last__}        = !defined $contents[ $i + 1 ];
        local $vars->{__odd__}         = ( $i % 2 ) == 0;
        local $vars->{__even__}        = ( $i % 2 ) == 1;
        local $vars->{__counter__}     = $i + 1;
        local $ctx->{__stash}{blog}    = $content_data->blog;
        local $ctx->{__stash}{blog_id} = $content_data->blog_id;
        local $ctx->{__stash}{content} = $content_data;

        my $ct_id        = $content_data->content_type_id;
        my $content_type = MT::ContentType->load($ct_id);
        local $ctx->{__stash}{content_type} = $content_type;

        my $out = $builder->build( $ctx, $tok, $cond );
        $res .= $out;
        $i++;
    }
    $res;
}

sub _hdlr_content {
    my ( $ctx, $args, $cond ) = @_;

    my $content      = $ctx->stash('content');
    my $content_type = $ctx->stash('content_type');

    my $f_json = $content_type->fields;
    my $f      = $f_json ? JSON::decode_json($f_json) : [];
    my @fields = sort { $a->{order} <=> $b->{order} } @$f;

    my $d_json = $content->data;
    my $datas = $d_json ? JSON::decode_json($d_json) : {};

    my $out = '';
    foreach my $f (@fields) {
        my $data = $datas->{ $f->{id} };
        $out .= "<div>$data</div>";
    }

    return $out;
}

sub _hdlr_entity {
    my ( $ctx, $args, $cond ) = @_;

    my $content = $ctx->stash('content');
    my $blog_id = $content->blog_id;

    my $terms;
    my $type = $args->{type};
    my $name = $args->{name};
    if ($type) {
        $terms = { unique_key => $type };
    }
    elsif ($name) {
        $terms = {
            blog_id => $blog_id,
            name    => $name,
        };
    }
    else {
        return $ctx->error(
            MT->translate('\'type\' or \'name\' is required.') );
    }
    my $content_field = MT::ContentField->load($terms);

    my $d_json = $content->data;
    my $datas = $d_json ? JSON::decode_json($d_json) : {};

    my $content_field_type
        = MT->registry('content_field_types')->{ $content_field->type };
    if ((      $content_field_type->{type} eq 'datetime'
            || $content_field->type eq 'date'
            || $content_field->type eq 'time'
        )
        && $datas->{ $content_field->id }
        )
    {
        $args->{ts}
            = $content_field->type eq 'date'
            ? $datas->{ $content_field->id } . '000000'
            : $content_field->type eq 'time'
            ? '19700101' . $datas->{ $content_field->id }
            : $datas->{ $content_field->id }
            unless $args->{ts};
        return $ctx->build_date($args);
    }
    else {
        return $datas->{ $content_field->id };
    }
}

sub _hdlr_assets {
    my ( $ctx, $args, $cond ) = @_;

    my $content    = $ctx->stash('content');
    my $blog_id    = $content->blog_id;
    my $ct_data_id = $content->id;

    my @assets = MT::Asset->load(
        { class => '*' },
        {   join => MT::ObjectAsset->join_on(
                undef,
                {   asset_id  => \'= asset_id',
                    object_ds => 'content_data',
                    object_id => $ct_data_id
                }
            )
        }
    );
    local $ctx->{__stash}{assets} = \@assets;

    require MT::Template::Tags::Asset;
    return MT::Template::Tags::Asset::_hdlr_assets(@_);
}

sub _hdlr_content_tags {
    my ( $ctx, $args, $cond ) = @_;

    require MT::Entry;
    my $content = $ctx->stash('content');
    return '' unless $content;
    my $glue = $args->{glue};

    local $ctx->{__stash}{tag_max_count} = undef;
    local $ctx->{__stash}{tag_min_count} = undef;
    local $ctx->{__stash}{all_tag_count} = undef;

    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    my $res     = '';
    my $i       = 1;
    my $vars    = $ctx->{__stash}{vars} ||= {};
    my $tags    = $content->get_tag_objects;
    my @tags    = @$tags;
    if ( !$args->{include_private} ) {
        @tags = grep { !$_->is_private } @tags;
    }
    for my $tag (@tags) {
        local $vars->{__first__}   = $i == 1;
        local $vars->{__last__}    = $i == scalar @tags;
        local $vars->{__odd__}     = ( $i % 2 ) == 1;
        local $vars->{__even__}    = ( $i % 2 ) == 0;
        local $vars->{__counter__} = $i;
        $i++;
        local $ctx->{__stash}{Tag}             = $tag;
        local $ctx->{__stash}{tag_count}       = undef;
        local $ctx->{__stash}{tag_entry_count} = undef;
        defined( my $out = $builder->build( $ctx, $tokens, $cond ) )
            or return $ctx->error( $builder->errstr );
        $res .= $glue if defined $glue && length($res) && length($out);
        $res .= $out;
    }
    $res;
}

sub _hdlr_content_categories {
    my ( $ctx, $args, $cond ) = @_;
    my $c = $ctx->stash('content')
        or return $ctx->_no_entry_error();
    my $content    = $ctx->stash('content');
    my $ct_data_id = $content->id;
    my $cats;
    require MT::ObjectCategory;
    my @obj_cats = MT::ObjectCategory->load(
        {   object_ds => 'content_data',
            object_id => $ct_data_id
        }
    );
    foreach my $obj_cat (@obj_cats) {
        my $cat = MT::Category->load( $obj_cat->category_id );
        push @$cats, $cat;
    }
    return '' unless $cats && @$cats;
    my $builder = $ctx->stash('builder');
    my $tokens  = $ctx->stash('tokens');
    my $res     = '';
    my $glue    = $args->{glue};
    local $ctx->{inside_mt_categories} = 1;

    my $i = 1;
    my $vars = $ctx->{__stash}{vars} ||= {};
    for my $cat (@$cats) {
        local $ctx->{__stash}->{category} = $cat;
        local $vars->{__first__}          = $i == 1;
        local $vars->{__last__}           = $i == scalar @$cats;
        local $vars->{__odd__}            = ( $i % 2 ) == 1;
        local $vars->{__even__}           = ( $i % 2 ) == 0;
        local $vars->{__counter__}        = $i;
        $i++;
        defined( my $out = $builder->build( $ctx, $tokens, $cond ) )
            or return $ctx->error( $builder->errstr );
        $res .= $glue if defined $glue && length($res) && length($out);
        $res .= $out;
    }
    $res;
}

1;
