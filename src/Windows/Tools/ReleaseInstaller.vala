namespace Windows.Tools {
    public class ReleaseInstaller : Gtk.Box {
        Gtk.Notebook notebook;
        Gtk.Button btnBack;
        Gtk.Button btnCancel;
        Gtk.ProgressBar progressBar;
        Gtk.TextBuffer textBuffer;
        bool cancelled;
        Thread<void> thread;
        string text;
        Models.Release release;

        // TODO Add message when trying to close the window if a download is in progress
        public ReleaseInstaller (Gtk.Notebook notebook, Gtk.Button btnBack) {
            //
            this.notebook = notebook;
            this.btnBack = btnBack;

            //
            set_orientation (Gtk.Orientation.VERTICAL);
            set_valign (Gtk.Align.CENTER);
            set_spacing (0);

            //
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 15);
            content.set_valign (Gtk.Align.CENTER);
            content.set_margin_bottom (15);
            content.set_margin_top (15);

            //
            progressBar = new Gtk.ProgressBar ();
            content.append (progressBar);

            //
            textBuffer = new Gtk.TextBuffer (new Gtk.TextTagTable ());

            //
            var textView = new Gtk.TextView ();
            textView.set_wrap_mode (Gtk.WrapMode.WORD_CHAR);
            textView.set_editable (false);
            textView.set_buffer (textBuffer);

            //
            var scrolledWindow = new Gtk.ScrolledWindow ();
            scrolledWindow.set_child (textView);
            scrolledWindow.set_min_content_height (200);
            content.append (scrolledWindow);

            //
            btnCancel = new Gtk.Button.with_label ("Cancel");
            btnCancel.set_hexpand (true);
            btnCancel.clicked.connect (() => Cancel ());
            content.append (btnCancel);

            //
            var clamp = new Adw.Clamp ();
            clamp.set_maximum_size (700);
            clamp.set_child (content);
            append (clamp);
        }

        void Cancel (bool showCancelMessage = true, bool isEnd = false) {
            if (!cancelled) cancelled = true;
            if (showCancelMessage) textBuffer.set_text (text += "Cancelled the install...");
            if (!isEnd) release.InstallCancelled = true;
            progressBar.set_fraction (0);
            btnCancel.set_sensitive (false);
            btnBack.set_sensitive (true);
            release = null;
        }

        public void Download (Models.Release release) {
            this.release = release;

            btnBack.set_sensitive (false);
            textBuffer.set_text (text = "Download started...\n");

            cancelled = false;
            bool done = false;
            bool requestError = false;
            bool downloadError = false;
            string errorMessage = "";
            double state = 0;

            thread = new Thread<void> ("download", () => {
                string url = release.DownloadURL;
                string path = release.Tool.Launcher.FullPath + "/" + release.Title + release.FileExtension;

                if (release.Tool.IsUsingGithubActions) {
                    Utils.Web.OldDownload (url, path, ref requestError, ref downloadError, ref errorMessage);
                } else {
                    Utils.Web.Download (url, path, ref state, ref cancelled, ref requestError, ref downloadError, ref errorMessage);
                }

                done = true;
            });

            int timeout_refresh = 75;
            if (release.Tool.IsUsingGithubActions) timeout_refresh = 500;

            GLib.Timeout.add (timeout_refresh, () => {
                if (requestError || downloadError) {
                    textBuffer.set_text (text += errorMessage);
                    Cancel (false);
                    return false;
                }

                if (cancelled) return false;

                if (release.Tool.IsUsingGithubActions) progressBar.pulse ();
                else progressBar.set_fraction (state);

                if (done) {
                    textBuffer.set_text (text += "Download done...\n");
                    Extract ();
                    return false;
                }

                return true;
            }, 1);
        }

        void Extract () {
            progressBar.set_pulse_step (1);
            textBuffer.set_text (text += "Extraction started...\n");

            bool done = false;
            bool error = false;

            thread = new Thread<void> ("extract", () => {
                string directory = release.Tool.Launcher.FullPath + "/";
                string sourcePath = Utils.File.Extract (directory, release.Title, release.FileExtension);

                if (sourcePath == "") {
                    error = true;
                    return;
                }

                if (release.Tool.IsUsingGithubActions) {
                    Utils.File.Extract (directory, sourcePath.substring (0, sourcePath.length - 4).replace (directory, ""), ".tar");
                }

                if (release.Tool.TitleType != Models.Tool.TitleTypes.NONE) {
                    string path = release.Tool.Launcher.FullPath + "/" + release.GetDirectoryName ();

                    Utils.File.Rename (sourcePath, path);

                    GLib.Timeout.add (1000, () => {
                        if (Utils.File.Exists (path)) return false;

                        return true;
                    }, 1);
                }

                release.Tool.Launcher.install (release);

                done = true;
            });

            GLib.Timeout.add (500, () => {
                if (error) {
                    textBuffer.set_text (text += "There was an error while extracting...");
                    Cancel (false);
                    return false;
                }

                if (cancelled) return false;

                progressBar.pulse ();

                if (done) {
                    textBuffer.set_text (text += "Extraction done...\n");
                    release.Installed = true;
                    release.SetSize ();
                    Cancel (false, true);

                    return false;
                }

                return true;
            }, 1);
        }
    }
}
