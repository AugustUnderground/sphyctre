import setuptools
 
package_name = 'sphyctre'

with open('README.md', 'r') as fh:
    long_description = fh.read()

with open('requirements.txt', 'r') as req:
    requirements = req.read().splitlines()
 
setuptools.setup( name                          = package_name
                , version                       = '0.0.1'
                , author                        = 'Yannick Uhlmann'
                , author_email                  = 'augustunderground@protonmail.com'
                , description                   = 'Spectre Simulation and Nutmeg Raw file handling in Python.'
                , long_description              = long_description
                , long_description_content_type = 'text/markdown'
                , url                           = 'https://github.com/electronics-and-drives/sphyctre'
                , packages                      = setuptools.find_packages()
                , classifiers                   = [ 'Development Status :: 2 :: Pre-Alpha'
                                                  , 'Programming Language :: Python :: 3'
                                                  , 'Operating System :: POSIX :: Linux' ]
                , python_requires               = '>=3.9'
                , install_requires              = requirements
                #, entry_points                  = { 'console_scripts': [ 'FIXME' ]}
                , package_data                  = { '': ['*.hy', '__pycache__/*']}
                , )
