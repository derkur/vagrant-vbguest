require "vagrant-vbguest/helpers/os_release"

module VagrantVbguest
  module Installers

    class Windows < Base

      def self.match?(vm)
        raise Error, _key: :do_not_inherit_match_method if self != Windows
        communicate_to(vm).test("(Get-WMIObject win32_operatingsystem).name")
      end

      def self.os_release(vm)
        @@os_release_info[vm_id(vm)] = communicate_to(vm).test(
          "(Get-WMIObject win32_operatingsystem).name"
        )
      end

      def os_release
        self.class.os_release(vm)
      end

      def tmp_path
        options[:iso_upload_path] || "$env:TEMP/VBoxGuestAdditions.iso"
      end

      def mount_point
        communicate.execute(
          "(Get-DiskImage -DevicePath (Get-DiskImage -ImagePath #{tmp_path}).DevicePath | Get-Volume).DriveLetter"
        ) do |type, data|
          return data.strip
        end
      end

      def installer_version(path_to_installer)
        version = nil
        communicate.execute("(get-item #{path_to_installer}).VersionInfo.ProductVersion", error_check: false) do |type, data|
          if (v = data.to_s.match(/(\d+\.\d+.\d+)/i))
            version = v[1]
          end
        end
        version
      end

      def install(opts = nil, &block)
        upload(iso_file)
        mount_iso(opts, &block)
        execute_installer(opts, &block)
        unmount_iso(opts, &block) unless options[:no_cleanup]
      end

      def running?(opts = nil, &block)
        communicate.test("get-service VBoxService", opts, &block)
      end

      def guest_version(reload = false)
        return @guest_version if @guest_version && !reload

        driver_version = super.to_s[/^(\d+\.\d+.\d+)/, 1]

        service_version = communicate.execute(
          "VBoxService --version", error_check: false
        )[1].to_s[/^(\d+\.\d+.\d+)/, 1]

        if service_version
          if driver_version != service_version
            @env.ui.warn(I18n.t(
              "vagrant_vbguest.guest_version_reports_differ",
              driver: driver_version, service: service_version)
            )
          else
            return service_version
          end
        end
        nil
      end

      def execute_installer(opts = nil, &block)
        yield_installation_warning(installer)
        opts = { error_check: false }.merge(opts || {})
        opts = { auto_reboot: true }.merge(opts || {})
        exit_status = communicate.execute("(Start-Process #{installer} /S -Wait).ExitCode", opts, &block)
        yield_installation_error_warning(installer) unless exit_status == 0
        exit_status
      end

      def installer
        @installer ||= File.join("#{mount_point}:", "VBoxWindowsAdditions.exe")
      end

      def mount_iso(opts = nil, &block)
        communicate.execute(
          "Mount-DiskImage -ImagePath #{tmp_path}", opts, &block
        )
        env.ui.info(I18n.t(
          "vagrant_vbguest.mounting_iso", mount_point: mount_point)
        )
      end

      def unmount_iso(opts = nil, &block)
        env.ui.info(I18n.t(
          "vagrant_vbguest.unmounting_iso",
          mount_point: mount_point)
        )
        communicate.execute(
          "Dismount-DiskImage -ImagePath #{tmp_path}", opts, &block
        )
        communicate.execute(
          "Remove-Item -Path #{tmp_path}", opts, &block
        )
      end

    end
  end
end
VagrantVbguest::Installer.register(VagrantVbguest::Installers::Windows, 2)