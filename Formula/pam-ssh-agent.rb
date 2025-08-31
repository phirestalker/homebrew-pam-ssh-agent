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
            signing_identity = "pam-signer"
            # On modern macOS, a valid, trusted code signing certificate is required.
            # We check for its existence before attempting to sign.
            unless system("security", "find-identity", "-v", "-p", "codesigning", "-s", signing_identity, out: File::NULL, err: File::NULL)
                odie <<~EOS
                Code signing certificate "#{signing_identity}" not found in your keychains.
                Please read the "macOS Security Configuration" instructions printed by
                `brew info #{name}` to create and trust the certificate,
                then run `brew reinstall #{name}`.
                EOS
            end

            # Create a minimal entitlements file. This signals to macOS that the binary
            # is aware of the modern security model, which can be necessary for it
            # to be loaded by platform binaries.
            (buildpath/"entitlements.plist").write <<~EOS
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            </dict>
            </plist>
            EOS

            system "/usr/bin/codesign", "--force", "--sign", signing_identity,
             "--options=runtime",
             "--entitlements", buildpath/"entitlements.plist",
             lib/"security/pam_ssh_agent.so"
        end
    end

    def caveats
        s = <<~EOS
        To use pam-ssh-agent, you must now configure your system's PAM service.
        The module was installed to:
        #{lib}/security/pam_ssh_agent.so

        EOS

        if OS.mac?
            s += <<~EOS
            ------------------------------------------------------------------
            **macOS Security Configuration (IMPORTANT):**

            This formula has built a statically-linked module. However, due to macOS's
            Hardened Runtime, you MUST sign the module with a locally created code
            signing certificate for it to be loaded by system processes like `sudo`.
            If you have not done so, please follow these steps:

            1. Open Spotlight by pressing (⌘ + Space), type "Keychain Access", and press Enter.
            2. In the menu bar, go to: Keychain Access > Certificate Assistant > Create a Certificate...
            3. Set:
            - Name: pam-signer
            - Identity Type: Self-Signed Root
            - Certificate Type: Code Signing
            4. Click "Create", then "Done".
            5. In Keychain Access, find the "pam-signer" certificate, double-click it,
            expand the "Trust" section, and set "When using this certificate:" to "Always Trust".
            6. After creating the certificate, reinstall this formula to apply the signature:
            brew reinstall ./pam-ssh-agent.rb
            ------------------------------------------------------------------

            **macOS PAM Configuration:**

            Edit the PAM configuration file (e.g., `/etc/pam.d/sudo`) and add the
            following line at the top, using the full path:

            auth       sufficient     #{lib}/security/pam_ssh_agent.so

            **Note on Symlinking:** A symlink is NOT created in a system directory
            (e.g., /usr/local/lib/pam) because modern macOS security policies require
            using the full, stable, and signed path from the Homebrew cellar.
            EOS
        end

        if OS.linux?
            # Detect standard PAM directories on Linux.
            pam_dir = ["/lib/x86_64-linux-gnu/security", "/lib64/security", "/lib/security"].find do |dir|
                File.directory?(dir)
            end

            s += <<~EOS
            **Linux Instructions:**

            To make the module available to your system's PAM service, create a
            symlink from the installed file to your system's security directory.
            EOS

            if pam_dir
                s += <<~EOS

                A standard PAM directory was detected at: #{pam_dir}
                Run the following command to create the link:

                sudo ln -sf "#{lib}/security/pam_ssh_agent.so" "#{pam_dir}/pam_ssh_agent.so"
                EOS
            else
                s += <<~EOS

                Could not automatically detect your system's PAM directory.
                Example command (replace with the correct path for your system):

                sudo ln -sf "#{lib}/security/pam_ssh_agent.so" /usr/lib/security/pam_ssh_agent.so
                EOS
            end

            s += <<~EOS

            After creating the symlink, edit the PAM configuration file
            (e.g., `/etc/pam.d/sudo`) and add this line at the top:

            auth       sufficient     pam_ssh_agent.so
            EOS
        end

        s
    end

    test do
        # A basic test to ensure the shared object file was installed.
        assert_predicate lib/"security/pam_ssh_agent.so", :exist?

        # On macOS, we can also check if the file is signed with a real identity.
        if OS.mac?
            (testpath/"codesign_output").write shell_output("/usr/bin/codesign -dv --entitlements - #{lib}/security/pam_ssh_agent.so 2>&1")
            # A successful run after cert creation will show "Authority=pam-signer".
            assert_match "Identifier=pam_ssh_agent", (testpath/"codesign_output").read
            assert_match "Authority=pam-signer", (testpath/"codesign_output").read
        end
    end
end

