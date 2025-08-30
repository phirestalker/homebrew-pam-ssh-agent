class PamSshAgent < Formula
    desc "PAM module for authentication with ssh-agent"
    homepage "https://github.com/nresare/pam-ssh-agent"
    url "https://github.com/nresare/pam-ssh-agent/archive/refs/tags/v0.9.4.tar.gz"
    sha256 "9b0f6d6aa72b4dbe6c3c6d6c6ce62081ed86519ad117451aa492fa73aabbfdb3"
    license "BSD-2-Clause"
    head "https://github.com/nresare/pam-ssh-agent.git", branch: "master"

    # Build dependencies
    depends_on "rust" => :build

    # Runtime dependencies
    depends_on "libssh"

    on_linux do
        depends_on "linux-pam"
    end

    def install
        # Build the Rust project in release mode
        system "cargo", "build", "--release", "--lib"

        # The library is built as `libpam_ssh_agent.so` or `libpam_ssh_agent.dylib`.
        # We need to install it as `pam_ssh_agent.so` in the standard PAM location
        # within the Homebrew prefix.
        lib_name = shared_library("pam_ssh_agent") # Resolves to libpam_ssh_agent.so or .dylib
        (lib/"security").install "target/release/#{lib_name}" => "pam_ssh_agent.so"
    end

    def caveats
        <<~EOS
        To use pam-ssh-agent, you must now configure your system's PAM service.
        The module was installed to:
        #{lib}/security/pam_ssh_agent.so

        **macOS Instructions:**

        You do NOT need to create a symlink on macOS. Instead, edit the PAM
        configuration file for the service you want (e.g., `/etc/pam.d/sudo`)
        and add the following line at the top, using the full path:

        auth       sufficient     #{lib}/security/pam_ssh_agent.so

        You will need root privileges to edit this file, for example:
        sudo nano /etc/pam.d/sudo

        **Linux Instructions:**

        1. First, create a symlink from the installed module to your system's
        PAM directory. The location varies by distribution:
        - Debian/Ubuntu: /lib/x86_64-linux-gnu/security/
        - RHEL/CentOS/Fedora: /lib64/security/
        - Arch Linux: /usr/lib/security/

        Example for a Debian-based system:
        sudo ln -sf "#{lib}/security/pam_ssh_agent.so" /lib/x86_64-linux-gnu/security/

        2. Next, edit the PAM configuration file (e.g., `/etc/pam.d/sudo`)
        and add this line at the top:

        auth       sufficient     pam_ssh_agent.so

        **General Configuration Options:**

        To use a specific set of authorized keys, you can add the `file` parameter:
        auth       sufficient     ...so file=~/.ssh/authorized_keys

        For more detailed information, please consult the project's README file.
        EOS
    end

    test do
        # A basic test to ensure the shared object file was installed.
        assert_predicate lib/"security/pam_ssh_agent.so", :exist?
    end
end

