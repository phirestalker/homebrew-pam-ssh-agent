class PamSshAgent < Formula
    desc "PAM module for authentication with ssh-agent"
    homepage "https://github.com/nresare/pam-ssh-agent"
    url "https://github.com/nresare/pam-ssh-agent/archive/refs/tags/v0.9.4.tar.gz"
    sha256 "9b0f6d6aa72b4dbe6c3c6d6c6ce62081ed86519ad117451aa492fa73aabbfdb3"
    license "BSD-2-Clause"
    head "https://github.com/nresare/pam-ssh-agent.git", branch: "master"

    # Build dependencies
    depends_on "rust" => :build
    depends_on "pkg-config" => :build

    # Runtime dependencies
    # libssh and openssl are linked statically on macOS
    on_linux do
        depends_on "libssh"
        depends_on "linux-pam"
        depends_on "openssl@3"
    end

    on_macos do
        # For static linking
        depends_on "libssh" => :build
        depends_on "openssl@3" => :build
        # For codesigning
        # depends_on :xcode => :build
    end

    def install
        if OS.mac?
            # On macOS, we build a self-contained binary by linking libssh and its
            # dependencies (like OpenSSL) statically. This avoids issues with SIP
            # and Library Validation when loading dylibs from a system process.
            # We use environment variables to instruct the dependency crates to link statically.
            ENV["LIBSSH_STATIC"] = "1"
            ENV["OPENSSL_DIR"] = Formula["openssl@3"].opt_prefix
            ENV["OPENSSL_STATIC"] = "1"
        end

        # Build the Rust project in release mode
        system "cargo", "build", "--release", "--lib"

        # The library is built as `libpam_ssh_agent.so` or `libpam_ssh_agent.dylib`.
        # We need to install it as `pam_ssh_agent.so` in the standard PAM location
        # within the Homebrew prefix.
        lib_name = shared_library("libpam_ssh_agent")
        (lib/"security").install "target/release/#{lib_name}" => "pam_ssh_agent.so"

        if OS.mac?
            # On macOS, the compiled library must be signed to be loaded by system processes
            # that are protected by the Hardened Runtime.
            system "/usr/bin/codesign", "--force", "--sign", "-", "--options=runtime", lib/"security/pam_ssh_agent.so"
        end
    end

    def caveats
        <<~EOS
        To use pam-ssh-agent, you must now configure your system's PAM service.
        The module was installed to:
        #{lib}/security/pam_ssh_agent.so

        **macOS Note:** This formula has built a statically-linked, self-contained
        module and signed it to comply with system security policies.

        **macOS Instructions:**

        You do NOT need to create a symlink. Edit the PAM configuration for
        the service you want (e.g., `/etc/pam.d/sudo`) and add the following
        line at the top, using the full path:

        auth       sufficient     #{lib}/security/pam_ssh_agent.so

        You will need root privileges to edit this file, for example:
        sudo nano /etc/pam.d/sudo

        **Linux Instructions:**

        1. First, create a symlink from the installed module to your system's
        PAM directory (e.g., /lib/x86_64-linux-gnu/security/):

        sudo ln -sf "#{lib}/security/pam_ssh_agent.so" /lib/x86_64-linux-gnu/security/

        2. Next, edit the PAM configuration file (e.g., `/etc/pam.d/sudo`)
        and add this line at the top:

        auth       sufficient     pam_ssh_agent.so

        **General Configuration Options:**

        To use a specific set of authorized keys, you can add the `file` parameter:
        auth       sufficient     ...so file=~/.ssh/authorized_keys
        EOS
        end

        test do
            # A basic test to ensure the shared object file was installed.
            assert_predicate lib/"security/pam_ssh_agent.so", :exist?

            # On macOS, we can also check if the file is signed.
            if OS.mac?
                (testpath/"codesign_output").write shell_output("/usr/bin/codesign -dv #{lib}/security/pam_ssh_agent.so 2>&1")
                assert_match "Signature=adhoc", (testpath/"codesign_output").read
                assert_match "Runtime Version", (testpath/"codesign_output").read
            end
        end
    end
