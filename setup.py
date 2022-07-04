
from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext

setup(
    name='cotta',
    description='Library for mapping yaml files to objects.',
    version='1.0.0',
    url='https://github.com/shaldokin/cotta',
    author='Shaldokin',
    author_email='shaldokin@protonmail.com',
    python_requires='>=3.0',
    install_requires=['cython', 'inflection', 'pyyaml'],
    classifiers=[
        'Programming Language :: Cython',
        'Programming Language :: Python :: 3 :: Only',
        'License :: OSI Approved :: MIT License',
    ],
    ext_modules=[
        Extension('cotta', sources=['cotta/cotta.pyx'],)
    ],
    cmdclass={'build_ext': build_ext}
)

