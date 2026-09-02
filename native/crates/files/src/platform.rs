use std::fs::{self, File, OpenOptions, Permissions};
use std::io;
use std::path::Path;

pub fn read_only(permissions: &Permissions) -> bool {
    platform_read_only(permissions)
}

#[cfg(not(windows))]
pub fn set_read_only(file: &File, mut permissions: Permissions, read_only: bool) -> io::Result<()> {
    platform_set_read_only(&mut permissions, read_only);
    file.set_permissions(permissions)
}

pub fn set_path_read_only(
    path: &Path,
    mut permissions: Permissions,
    read_only: bool,
) -> io::Result<()> {
    platform_set_read_only(&mut permissions, read_only);
    fs::set_permissions(path, permissions)
}

pub fn create_private_file(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    configure_private_file(&mut options);
    options.open(path)
}

pub fn create_private_directory(path: &Path) -> io::Result<()> {
    let mut builder = fs::DirBuilder::new();
    configure_private_directory(&mut builder);
    builder.create(path)
}

#[cfg(feature = "lane")]
pub fn open_read_nonblocking(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.read(true);
    configure_nonblocking_read(&mut options);
    options.open(path)
}

#[cfg(unix)]
fn platform_read_only(permissions: &Permissions) -> bool {
    use std::os::unix::fs::PermissionsExt;
    permissions.mode() & 0o222 == 0
}

#[cfg(not(unix))]
fn platform_read_only(permissions: &Permissions) -> bool {
    permissions.readonly()
}

#[cfg(unix)]
fn platform_set_read_only(permissions: &mut Permissions, read_only: bool) {
    use std::os::unix::fs::PermissionsExt;
    let mode = permissions.mode();
    permissions.set_mode(if read_only {
        mode & !0o222
    } else {
        mode | 0o222
    });
}

#[cfg(not(unix))]
fn platform_set_read_only(permissions: &mut Permissions, read_only: bool) {
    permissions.set_readonly(read_only);
}

#[cfg(unix)]
fn configure_private_file(options: &mut OpenOptions) {
    use std::os::unix::fs::OpenOptionsExt;
    options.mode(0o600);
}

#[cfg(not(unix))]
fn configure_private_file(_options: &mut OpenOptions) {}

#[cfg(unix)]
fn configure_private_directory(builder: &mut fs::DirBuilder) {
    use std::os::unix::fs::DirBuilderExt;
    builder.mode(0o700);
}

#[cfg(not(unix))]
fn configure_private_directory(_builder: &mut fs::DirBuilder) {}

#[cfg(all(feature = "lane", unix))]
fn configure_nonblocking_read(options: &mut OpenOptions) {
    use std::os::unix::fs::OpenOptionsExt;
    options.custom_flags(libc::O_NONBLOCK);
}

#[cfg(all(feature = "lane", not(unix)))]
fn configure_nonblocking_read(_options: &mut OpenOptions) {}

#[cfg(not(windows))]
pub fn replace(from: &Path, to: &Path) -> io::Result<()> {
    fs::rename(from, to)
}

#[cfg(windows)]
pub fn replace(from: &Path, to: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
    };

    let from: Vec<u16> = from.as_os_str().encode_wide().chain(Some(0)).collect();
    let to: Vec<u16> = to.as_os_str().encode_wide().chain(Some(0)).collect();
    // SAFETY: both vectors are terminated UTF-16 paths and remain alive for
    // the duration of the call. MoveFileExW retains neither pointer.
    let moved = unsafe {
        MoveFileExW(
            from.as_ptr(),
            to.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if moved == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(all(feature = "lane", unix))]
pub fn sync_parent(path: &Path) -> io::Result<()> {
    File::open(path.parent().unwrap_or_else(|| Path::new(".")))?.sync_all()
}

#[cfg(all(feature = "lane", not(unix)))]
pub fn sync_parent(_path: &Path) -> io::Result<()> {
    Ok(())
}
