"""Makes the .docx and .odt versions of the Photo Downloader documents from their .md files.

Every document except README.md is kept in three formats: .md (the source), .docx and .odt.
Run it after changing a document:   python docs/make_formats.py
Other .md files can be given as arguments:   python docs/make_formats.py path/to/file.md
Needs pandoc (https://pandoc.org) on the PATH.
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repository folder

# the current documents (older dated copies such as User_Manual.0.1.0.build.57.md are left as they are)
DOCS = [
    'docs/Specification_Current.md',
    'docs/User_Manual.md',
    'docs/Settings_File.md',
    'docs/Linux_Build.md',
    'docs/Plugin_Developer_Manual.md',
    'docs/Plugin_Plan.md',
    'GitHub/Release_Notes_0.1.2.1.md',
    'GitHub/Release_Notes_0.1.3.1.md',
    'GitHub/Release_Notes_0.1.4.1.md',
]

# copies of a document kept in a second place (the website folder)
COPIES = {
    'docs/User_Manual.md': 'GitHub/docs/User_Manual',
}


def convert(md):
    """Writes <name>.docx and <name>.odt next to the .md file; images are found relative to it."""
    folder = os.path.dirname(md) or '.'
    base = os.path.splitext(md)[0]
    for ext in ('docx', 'odt'):
        subprocess.run(['pandoc', md, '--resource-path', folder, '-o', base + '.' + ext], check=True)
        print('  ' + os.path.relpath(base + '.' + ext, ROOT))


def main():
    files = sys.argv[1:] or [os.path.join(ROOT, d) for d in DOCS]
    for md in files:
        md = os.path.abspath(md)
        print(os.path.relpath(md, ROOT))
        convert(md)
        rel = os.path.relpath(md, ROOT).replace(os.sep, '/')
        if rel in COPIES:  # the website copy: same text in all three formats
            dst = os.path.join(ROOT, COPIES[rel])
            shutil.copyfile(md, dst + '.md')
            for ext in ('docx', 'odt'):
                shutil.copyfile(os.path.splitext(md)[0] + '.' + ext, dst + '.' + ext)
            print('  copied to ' + COPIES[rel] + '.md/.docx/.odt')


if __name__ == '__main__':
    main()
