import sys

try:
    import semver
except ImportError:
    print("Error: 'semver' module not found. Please run: pip install semver")
    sys.exit(1)

def bump_version(current_tag):
    if not current_tag or current_tag == "null" or current_tag == "None":
        return "v1.0.0"
    
    clean_tag = current_tag.lstrip('v')
    
    try:
        ver = semver.VersionInfo.parse(clean_tag)
        new_ver = ver.bump_patch()
        return f"v{new_ver}"
    except ValueError:
        return "v1.0.0"

if __name__ == "__main__":
    latest_tag = sys.argv[1] if len(sys.argv) > 1 else None
    new_tag = bump_version(latest_tag)
    print(new_tag)