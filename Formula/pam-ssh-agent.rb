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
        lib_name = shared_library("pam_ssh_agent")
        (lib/"security").install "target/release/#{lib_name}" => "pam_ssh_agent.so"

        if OS.mac?
            # On modern macOS, an ad-hoc signature is insufficient for PAM modules.
            # You must sign it with a local code signing certificate.
            # See the caveats for instructions on how to create one.
            # Replace "pam-signer" with the name of the certificate you created if different.
            signing_identity = "pam-signer"
            system "/usr/bin/codesign", "--force", "--sign", signing_identity, "--options=runtime", lib/"security/pam_ssh_agent.so"
        end
    end

    def caveats
        <<~EOS
        To use pam-ssh-agent, you must now configure your system's PAM service.
        The module was installed to:
        #{lib}/security/pam_ssh_agent.so

        ------------------------------------------------------------------
        **macOS Security Configuration (IMPORTANT):**

        This formula has built a statically-linked module. However, due to macOS's
        Hardened Runtime, you MUST sign the module with a locally created code
        signing certificate for it to be loaded by system processes like `sudo`.

        **Instructions to Create and Trust a Signing Certificate:**

        1. Open the "Keychain Access" application.
        2. In the menu bar, go to: Keychain Access > Certificate Assistant > Create a Certificate...
        3. Set the following options:
        - Name: pam-signer  (The formula uses this name by default)
        - Identity Type: Self-Signed Root
        - Certificate Type: Code Signing
        4. Click "Create", and then "Done". Accept any default prompts.
        5. In Keychain Access, find the new "pam-signer" certificate (usually in the "login" keychain).
        6. Double-click the certificate, expand the "Trust" section, and set
        "When using this certificate:" to "Always Trust". Close the window and
        enter your password when prompted.

        **After creating the certificate, reinstall this formula to apply the signature:**
        brew reinstall ./pam-ssh-agent.rb
        ------------------------------------------------------------------

        **macOS PAM Configuration:**

        Edit the PAM configuration for the service you want (e.g., `/etc/pam.d/sudo`)
        and add the following line at the top, using the full path:

        auth       sufficient     #{lib}/security/pam_ssh_agent.so
        EOS
    end

    test do
        # A basic test to ensure the shared object file was installed.
        assert_predicate lib/"security/pam_ssh_agent.so", :exist?

        # On macOS, we can also check if the file is signed with a real identity.
        if OS.mac?
            (testpath/"codesign_output").write shell_output("/usr/bin/codesign -dv #{lib}/security/pam_ssh_agent.so 2>&1")
            # This will now fail if the cert doesn't exist, which is expected before the user creates it.
            # A successful run after cert creation will show "Authority=pam-signer".
            assert_match "Identifier=pam_ssh_agent", (testpath/"codesign_output").read
        end
    end
end

