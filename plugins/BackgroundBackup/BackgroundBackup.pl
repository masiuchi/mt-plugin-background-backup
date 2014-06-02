package MT::Plugin::BackgroundBackup;
use strict;
use warnings;
use utf8;
use base qw( MT::Plugin );

use MT::CMS::Tools;
use MT::Util;

my $backing_up_message = 'Backing up now. Please wait.';
my $restoring_message  = 'Restoring now. Please wait.';

my $plugin = __PACKAGE__->new(
    {   name    => 'BackgroundBackup',
        version => 0.01,

        author_name => 'masiuchi',
        author_link => 'https://github.com/masiuchi',

        plugin_link =>
            'https://github.com/masiuchi/mt-plugin-background-backup',
        description =>
            '<__trans phrase="Execute backup/restoration in background.">',

        settings => MT::PluginSettings->new(
            [   [ 'backing_up',    { Default => undef } ],
                [ 'backup_result', { Default => undef } ],

                [ 'restoring',      { Default => undef } ],
                [ 'restore_result', { Default => undef } ],
            ]
        ),

        registry => {
            applications => {
                cms => {
                    callbacks => {
                        'template_source.backup'  => \&_tmpl_src_backup,
                        'template_source.restore' => \&_tmpl_src_restore,
                    },
                },
            },

            l10n_lexicon => {
                ja => {
                    'Execute backup/restoration in background.' =>
                        'バックアップ／バックアップの復元をバックグラウンドで実行します。',
                    $backing_up_message =>
                        'バックアップ中です。しばらくお待ちください。',
                    $restoring_message =>
                        'バックアップの復元中です。しばらくお待ちください。',
                },
            },
        },
    }
);
MT->add_plugin($plugin);

{
    my $backup = \&MT::CMS::Tools::backup;
    no warnings 'redefine';
    *MT::CMS::Tools::backup = sub {
        my $app = shift;

        my $backing_up = $plugin->get_config_value('backing_up');
        if ( !$backing_up ) {
            $plugin->set_config_value( 'backing_up', 1 );

            local *MT::Util::launch_background_tasks = sub {1};
            MT::Util::start_background_task(
                sub {
                    local *MT::App::send_http_header = sub { };
                    my $result = '';
                    local *MT::App::print
                        = sub { my $app = shift; $result .= join( '', @_ ) };

                    $backup->( $app, @_ );

                    $plugin->set_config_value( 'backup_result', $result );
                    $plugin->set_config_value( 'backing_up',    undef );
                }
            );
        }

        my $blog_id = $app->blog ? $app->blog->id : 0;
        return $app->redirect(
            $app->uri(
                mode => 'start_backup',
                args => { blog_id => $blog_id },
            )
        );
    };
}

{
    my $restore = \&MT::CMS::Tools::restore;
    no warnings 'redefine';
    *MT::CMS::Tools::restore = sub {
        my $app = shift;

        my $restoring = $plugin->get_config_value('restoring');
        if ( !$restoring ) {

            $plugin->set_config_value( 'restoring', 1 );

            local *MT::Util::launch_background_tasks = sub {1};
            MT::Util::start_background_task(
                sub {
                    local *MT::App::send_http_header = sub { };
                    my $result = '';
                    local *MT::App::print
                        = sub { my $app = shift; $result .= join( '', @_ ) };

                    $restore->( $app, @_ );

                    $plugin->set_config_value( 'restore_result', $result );
                    $plugin->set_config_value( 'restoring',      undef );
                }
            );
        }

        my $blog_id = $app->blog ? $app->blog->id : 0;
        return $app->redirect(
            $app->uri(
                mode => 'start_restore',
                args => { blog_id => $blog_id },
            )
        );
    };
}

{
    my $start_backup = \&MT::CMS::Tools::start_backup;
    no warnings 'redefine';
    *MT::CMS::Tools::start_backup = sub {
        my $app = shift;

        my $backup_result = $plugin->get_config_value('backup_result');
        if ($backup_result) {
            $plugin->set_config_value( 'backup_result', undef );
            return $backup_result;
        }
        else {
            return $start_backup->( $app, @_ );
        }
    };
}

{
    my $start_restore = \&MT::CMS::Tools::start_restore;
    no warnings 'redefine';
    *MT::CMS::Tools::start_restore = sub {
        my $app = shift;

        my $restore_result = $plugin->get_config_value('restore_result');
        if ($restore_result) {
            $plugin->set_config_value( 'restore_result', undef );
            return $restore_result;
        }
        else {
            return $start_restore->( $app, @_ );
        }
    };
}

sub _tmpl_src_backup {
    my ( $cb, $app, $tmpl ) = @_;

    return unless _is_backing_up() || _is_restoring();

    {
        my $message
            = _is_backing_up() ? $backing_up_message : $restoring_message;
        $message = $plugin->translate($message);

        my $insert = quotemeta '<mt:if name="error">';
        my $mtml   = <<"__MTML__";
<mtapp:statusmsg
  id="backing-up"
  class="info"
  can_close="0">
  $message
</mtapp:statusmsg>

__MTML__
        $$tmpl =~ s/($insert)/$mtml$1/;
    }

    {
        my $before = quotemeta '<div id="backup-panel">';
        my $after  = '<div id="backup-panel" style="display: none;">';
        $$tmpl =~ s/$before/$after/;
    }
}

sub _tmpl_src_restore {
    my ( $cb, $app, $tmpl ) = @_;

    return unless _is_backing_up() || _is_restoring();

    {
        my $message
            = _is_backing_up() ? $backing_up_message : $restoring_message;
        $message = $plugin->translate($message);

        my $insert = quotemeta '<mt:if name="error">';
        my $mtml   = <<"__MTML__";
<mtapp:statusmsg
  id="restoring"
  class="info"
  can_close="0">
  $message
</mtapp:statusmsg>

__MTML__
        $$tmpl =~ s/($insert)/$mtml$1/;
    }

    {
        my $before = quotemeta '<div id="restore-panel">';
        my $after  = '<div id="restore-panel" style="display: none;">';
        $$tmpl =~ s/$before/$after/;
    }

}

sub _is_backing_up {
    return $plugin->get_config_value('backing_up') ? 1 : undef;
}

sub _is_restoring {
    return $plugin->get_config_value('restoring') ? 1 : undef;
}

1;
