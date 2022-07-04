
# cython: language_level=3

# import dependencies
import datetime, re, os
from types import MethodType
import yaml, inflection

try:
    import pandas as pd
    pandas_imported = True
except ImportError:
    pandas_imported = False

cdef extern from * nogil:
    cdef T reinterpret_cast[T](void*)

cdef extern from "Python.h":
    cdef cppclass PyObject
    list PyList_New(int size)
    void PyList_SetItem(list lst, int index, value)
    int PyLong_Check(obj)
    int PyFloat_Check(obj)
    int PyUnicode_Check(obj)
    int PyList_Check(obj)
    int PyTuple_Check(obj)
    int PyDict_Check(obj)

    int PyDict_Next(obj, int pos, key, value)

# globals
cdef dict class_objs = {}

# util
cpdef kabob(str text):
    return inflection.underscore(text).replace('_', '-')

# cotta class head
cdef class CottaClassHead:

    cdef object classobj
    cdef str name
    cdef int has_global_key;
    cdef str global_key
    cdef list fields
    cdef dict instances

    def __init__(self, classobj, str name):
        self.classobj = classobj
        self.name = name
        self.fields = []
        self.has_global_key = 0
        self.instances = {}

    cpdef get(self, key, default, int is_list=0):
        cdef list outputs
        cdef int count
        cdef int index
        if is_list:
            count = len(key)
            outputs = PyList_New(count)
            for index in range(count):
                PyList_SetItem(outputs, index, self.instances.get(key[index], default))
            return outputs
        else:
            return self.instances.get(key, default)

    cpdef add_to_global(self, this):
        cdef object g_key
        if self.has_global_key:
            g_key = getattr(this, self.global_key)
            if g_key is not None:
                self.instances[g_key] = this

    cdef init(self, this, kwargs):
        for each in self.fields:
            each.init(this, kwargs)
        self.add_to_global(this)

    cpdef to_data(self, this, dict data):
        cdef Field each
        data['class'] = self.name
        for each in self.fields:
            each.to_data(this, data)

    cpdef from_data(self, this, dict data):
        cdef Field e_field
        for e_field in self.fields:
            e_field.from_data(this, data)
        self.add_to_global(this)

    cpdef remove(self, obj, int remove_global=1):
        if remove_global == 1:
            if self.has_global_key:
                del self.instances[getattr(obj, self.global_key)]
            all_instances.remove(obj)
        else:
            if not self.has_global_key:
                all_instances.remove(obj)

    cpdef fill(self, obj):
        cdef Field e_field
        for e_field in self.fields:
            e_field.fill(obj)

# field
cdef class Field(object):

    cdef CottaClassHead head
    cdef object default
    cdef str kind
    cdef object refr_class
    cdef str name
    cdef object def_name
    cdef str dict_name
    cdef object def_dict_name
    cdef int required
    cdef int ignore_if_null
    cdef object conv
    cdef object conv_to
    cdef object _special_from
    cdef object _special_to

    def __init__(self, default=None, str kind='', refr_class=None, ignore_if_null=True, special_from=None, special_to=None, conv=None, conv_to=None, name=None, dict_name=None):
        self.default = default
        self.kind = kind
        self.refr_class = refr_class
        self.name = ''
        self.dict_name = ''
        self.ignore_if_null = ignore_if_null
        self.conv = conv
        self.conv_to = conv_to
        self._special_from = special_from
        self._special_to = special_to
        self.def_name = name
        self.def_dict_name = dict_name

    cpdef new_class_init(self, str name, CottaClassHead head, classobj):

        # set name
        self.head = head
        if self.def_name is None:
            self.name = name
        else:
            self.name = self.def_name
        if self.def_dict_name is None:
            self.dict_name = name.lower().replace('_', '-')
        else:
            self.dict_name = self.def_dict_name

        # add to head
        head.fields.append(self)

    cpdef to_data(self, obj, dict data):
        if hasattr(obj, self.name):
            value = getattr(obj, self.name)
            if self.kind == 'refr':
                if value is not None:
                    value = getattr(value, self.head.global_key)
            elif self.kind == 'refr-list':
                if value is not None:
                    value = [getattr(item, self.head.global_key) for item in value]
            elif self.kind == 'single':
                f_data = {}
                if value is not None:
                    value.__cotta__.to_data(value, f_data)
                    del f_data['class']
                    value = f_data
            elif self.kind == 'single-list':
                if value is not None:
                    n_value = []
                    for item in value:
                        i_data = {}
                        item.__cotta__.to_data(item, i_data)
                        del i_data['class']
                        n_value.append(i_data)
                    value = n_value
            elif self.kind == 'special':
                if self._special_to:
                    value = self._special_to(obj, value)
            if self.conv_to:
                value = self.conv_to(value)
            if not (self.ignore_if_null and value is None):
                data[self.dict_name] = value

    cpdef from_data(self, obj, dict data):
        value = data.get(self.dict_name, self.default)
        if self.kind == 'special':
            if self._special_from is not None:
                value = self._special_from(obj, value)
        if self.conv is not None:
            value = self.conv(value)
        setattr(obj, self.name, value)

    cpdef special_to(self, func):
        self._special_to = func
        return func

    cpdef special_from(self, func):
        self._special_from = func
        return func

    cpdef init(self, obj, dict kwargs):
        setattr(obj, self.name, kwargs.get(self.name, self.default))

    def fill(self, obj):

        # c vars
        cdef list r_items
        cdef object o_value
        cdef dict o_dict

        # is this a special kind?
        if self.kind:
            o_value = getattr(obj, self.name)
            if o_value is not None:

                # set values
                if self.kind == 'refr':
                    setattr(obj, self.name, get(self.refr_class, o_value))

                elif self.kind == 'refr-list':
                    r_items = o_value
                    setattr(obj, self.name, [get(self.refr_class, item) for item in r_items])

                elif self.kind == 'single':
                    o_obj = class_objs[self.refr_class](init=False)
                    init_new_obj(obj.__cotta_file__, o_obj, o_value, lambda: o_obj.__cotta__.from_data(o_obj, o_value))
                    setattr(obj, self.name, o_obj)

                elif self.kind == 'single-list':
                    o_class = class_objs[self.refr_class]
                    r_items = []
                    for o_dict in o_value:
                        o_item = o_class(init=False)
                        init_new_obj(obj.__cotta_file__, o_item, o_dict, lambda: o_item.__cotta__.from_data(o_item, o_dict))
                        r_items.append( o_item )
                    setattr(obj, self.name, r_items)

# new class
cdef list all_instances = []

cdef class CottaInitFunc:

    cdef CottaClassHead head
    cdef int type

    cdef dict batch_inits
    cdef object batch_init_funcs

    def __init__(self):
        self.batch_inits = {}

    def __call__(self, this):
        if self.type == 1:
            meth = self.__cotta_init__
        elif self.type == 2:
            meth = self.__cotta_on_init__
        elif self.type == 3:
            meth = self.__cotta_on_batch_init__
        return MethodType(meth, this)

    def __cotta_init__(self, this, init=True, **kwargs):
        all_instances.append(this)
        if init:
            this.__cotta_on_init__(init, kwargs)

    cpdef __cotta_on_init__(self, this, init, kwargs):
        init_new_obj(kwargs.get('__cotta_file__'), this, kwargs, HeadInitLambda(self.head, this, kwargs))

    cpdef __cotta_on_batch_init__(self, this, list items):
        if not this.__cotta_batch_initiated__:
            this.__cotta_batch_init__(items)
            this.__cotta_batch_initiated__ = True


cdef class HeadInitLambda(object):

    cdef CottaClassHead head
    cdef object obj
    cdef dict kwargs
    cdef int from_data

    def __init__(self, CottaClassHead head, obj, dict kwargs, int from_data=0):
        self.head = head
        self.obj = obj
        self.kwargs = kwargs
        self.from_data = from_data

    def __call__(self):
        self.call()

    cpdef call(self):
        if self.from_data:
            self.head.from_data(self.obj, self.kwargs)
        else:
            self.head.init(self.obj, self.kwargs)

cdef class CottaBatchInitFunc(object):

    # members
    cdef int initiated

    # construction
    def __init__(self):
        self.initiated = 0

    # call
    def __call__(self, this, items):
        if self.initiated == 0:
            this.__cotta_batch_init__(items)
            self.initiated = 1

cpdef init_new_obj(yaml_file, obj, dict data, func):
    cdef YamlFile y_file
    setattr(obj, '__cotta_file__', yaml_file)
    if hasattr(obj, '__cotta_before_init__'):
        obj.__cotta_before_init__(data)
    func()
    if hasattr(obj, '__cotta_after_init__'):
        obj.__cotta_after_init__(data)

cdef class new_class(object):

    cdef object name
    cdef object global_key

    def __init__(self, name=None, global_key=None):
        self.name = name
        self.global_key = global_key

    def __call__(self, classobj):
        return self.call(classobj)

    cpdef call(self, classobj):

        # start
        if self.name is None:
            name = kabob(self.name or classobj.__name__)
        class_objs[name] = classobj

        head = CottaClassHead(classobj, str(name))
        setattr(classobj, '__cotta__', head)
        setattr(classobj, '__cotta_name__', name)
        setattr(classobj, '__cotta_fields__', head.fields)
        setattr(classobj, '__cotta_instances__', head.instances)

        cdef CottaInitFunc init_func
        init_func = CottaInitFunc()
        init_func.type = 1
        init_func.head = head
        setattr(classobj, '__init__', property(init_func))

        cdef CottaInitFunc on_init_func
        on_init_func = CottaInitFunc()
        on_init_func.type = 2
        on_init_func.head = head
        setattr(classobj, '__cotta_on_init__', property(on_init_func))

        cdef CottaInitFunc batch_init_func
        if hasattr(classobj, '__cotta_batch_init__'):
            batch_init_func = CottaInitFunc()
            batch_init_func.type = 3
            batch_init_func.head = head
            setattr(classobj, '__cotta_on_batch_init__', property(batch_init_func))
            setattr(classobj, '__cotta_batch_initiated__', False)

        # go through attrs
        for a_enum, a_name in enumerate(dir(classobj)):
            attr = getattr(classobj, a_name)

            # field
            if isinstance(attr, Field):
                attr.new_class_init(a_name, head, classobj)

        # global key
        head.has_global_key = self.global_key is not None
        if head.has_global_key:
            head.global_key = self.global_key

        # finished!
        return classobj

# string
custom_loader_fail = object()

cdef dict custom_dumpers = {}
cdef list custom_loaders = []

def custom_dumper(classobj):
    def __string_dumper_wrap__(func):
        custom_dumpers[classobj] = func
        return func
    return __string_dumper_wrap__

def custom_loader(func):
    custom_loaders.append(func)
    return func

# datetime
def default_to_datetime_func(obj):
    obj = datetime.datetime.strptime(obj)
    if isinstance(obj, datetime.date):
        return datetime.datetime(
            year=obj.year,
            month=obj.month,
            day=obj.day
        )

to_datetime_func = default_to_datetime_func

cdef list datetime_formats = [
    '%Y-%m-%d',
    '%Y-%m-%d %H',
    '%Y-%m-%d %H:%M',
    '%Y-%m-%d %H:%M:%S',
    '%Y-%m-%d %H:%M:%S.%f',
]

cdef _numstr(int num, int size=2):
    cdef str _n
    _n = str(num)
    while len(_n) < size:
        _n = '0' + _n
    return _n

@custom_dumper(datetime.date)
def date_dumper(obj):
    return f'{obj.year}-{_numstr(obj.month)}-{_numstr(obj.day)}'

@custom_dumper(datetime.datetime)
def datetime_dumper(obj):
    return f'{obj.year}-{_numstr(obj.month)}-{_numstr(obj.day)} {_numstr(obj.hour)}:{_numstr(obj.minute)}:{_numstr(obj.second)}'

@custom_loader
def datetime_loader(obj):
    if PyUnicode_Check(obj):
        for pattern in datetime_formats:
            try:
                tm = to_datetime_func(obj, pattern)
                return tm
            except:
                pass
    return custom_loader_fail

# time delta
timedelta_capture = re.compile('((?P<weeks>\d+?)\s*wks)?\s*((?P<days>\d+?)\s*days)?\s*((?P<hours>\d+?)\s*hrs)?\s*((?P<minutes>\d+?)\s*mins)?\s*((?P<seconds>\d+?)\s*secs)?\s*((?P<milliseconds>\d+?)\s*millis)?\s*((?P<microseconds>\d+?)\s*micros)?')

@custom_dumper(datetime.timedelta)
def custom_timedelta_dumper(obj):
    cdef str output = ""
    if obj:
        if obj.days:
            output += str(obj.days) + ' days'
        if obj.seconds:
            output += str(obj.seconds) + ' secs'
        if obj.microseconds:
            output += str(obj.seconds) + ' micros'
    else:
        output = '0 micros'
    return output
if pandas_imported:
    custom_dumper(pd._libs.tslibs.timedeltas.Timedelta)(custom_timedelta_dumper)

@custom_loader
def load_timedelta(deltastring):

    # start
    if PyUnicode_Check(deltastring):
        match = timedelta_capture.match(deltastring)
        pieces = match.groupdict()

        # does this match?
        if not all(piece is None for piece in pieces.values()):
            for key in pieces:
                if pieces[key] is None:
                    pieces[key] = 0
                else:
                    pieces[key] = int(pieces[key])
            return datetime.timedelta(**pieces)

    # nope
    return custom_loader_fail

# utility
def get(str class_name, key, default=None):
    return class_objs[class_name].__cotta__.get(key, default)

def new(str class_name, **kwargs):
    return class_objs[class_name](**kwargs)

cdef class BatchInitSortFunction:

    cdef list items
    cdef int count

    def __init__(self, items):
        self.items = items
        self.count = len(items)

    def __call__(self, item):
        if hasattr(item, '__cotta_batch_init_sort__'):
            return item.__cotta_batch_init_sort__(self.items)
        else:
            return self.count

# yaml file
cdef dict yaml_files = {}

cpdef get_yaml_file(str path):
    get = yaml_files.get(path)
    if get is None:
        get = YamlFile(path, None, os.path.getmtime(path))
        yaml_files[path] = get
    return get

cdef class YamlFile:

    cdef str _path
    cdef object item
    cdef object mod_time

    def __init__(self, str path, item, mod_time):
        self._path = path
        self.item = item
        self.mod_time = mod_time
        yaml_files[path] = self

    cpdef refresh(self):
        mod_time_check = os.path.getmtime(self._path)
        if mod_time_check > self.mod_time:
            self.mod_time = mod_time_check
            _load_from(self._path, 1)

    cpdef dump(self):
        dump_to(self.item, self._path)

    @property
    def path(self):
        return self._path

cpdef refresh(obj=None):
    cdef YamlFile y_file
    if obj is None:
        for y_file in yaml_files.values():
            y_file.refresh()
    else:
        if hasattr(obj, '__cotta__'):
            if obj.__cotta_file__ is not None:
                obj.__cotta_file__.refresh()

# yaml integration
def get_constructor(loader, node):
    return get(node.value[0].value, node.value[1].value)
yaml.add_constructor(u'!get', get_constructor)

# dump
class TypeNotSupported(BaseException):
    def __init__(self, type):
        self.type = type
        self.message = f'The type "{type}" is not yet supported, create a dumper for this type to support it'

cdef object dump_is_comment = re.compile('\A\s*\#')

cpdef _dump_obj(str tabs, obj, int nl):

    cdef str n_tabs
    cdef int o_int
    cdef int o_last_index
    cdef int o_index
    cdef str o_str
    cdef list o_list
    cdef tuple o_tuple
    cdef dict o_dict
    cdef list o_order
    cdef str o_key
    cdef object d_key
    cdef object d_value
    cdef int has_adorn

    # none
    if obj is None:
        return 'null'

    # bool
    elif obj is True:
        return 'true'
    elif obj is False:
        return 'false'

    # number
    elif PyLong_Check(obj) or PyFloat_Check(obj):
        return str(obj)

    # string
    elif PyUnicode_Check(obj):
        if ':' in obj:
            return '"' + obj.replace('"', '\\"') + '"'
        else:
            return obj

    # list
    elif PyList_Check(obj):
        o_str = ''
        o_list = obj
        o_int = len(obj)
        o_last_index = o_int - 1
        n_tabs = tabs + '  '
        if nl:
            o_str += '\n' + tabs
        for o_index in range(o_int):
            if o_index:
                o_str += tabs
            o_str += '- ' + _dump_obj(n_tabs, o_list[o_index], 0)
            if o_index < o_last_index:
                o_str += '\n'
        return o_str

    # tuple
    elif PyTuple_Check(obj):
        o_str = ''
        o_tuple = obj
        o_int = len(obj)
        o_last_index = o_int - 1
        n_tabs = tabs + '  '
        if nl:
            o_str += '\n' + tabs
        for o_index in range(o_int):
            if o_index:
                o_str += tabs
            o_str += '- ' + _dump_obj(n_tabs, o_tuple[o_index], 0)
            if o_index < o_last_index:
                o_str += '\n'
        return o_str

    # dict
    elif PyDict_Check(obj):

        o_str = ''
        n_tabs = tabs + '  '
        o_dict = obj
        o_int = len(o_dict)
        o_last_index = o_int - 1
        o_index = 0

        if nl:
            o_str += '\n' + tabs

        for d_key in o_dict:

            if o_index:
                o_str += tabs

            o_str += _dump_obj(n_tabs, d_key, 0)
            o_str += ': '
            o_str += _dump_obj(n_tabs, o_dict[d_key], 1)

            if o_index < o_last_index:
                o_str += '\n'
            o_index += 1

        return o_str

    # cotta object
    elif hasattr(obj, '__cotta__'):

        o_dict = {}
        if hasattr(obj, '__cotta_before_dump__'):
            obj.__cotta_before_dump__(o_dict)
        obj.__cotta__.to_data(obj, o_dict)
        if hasattr(obj, '__cotta_after_dump__'):
            obj.__cotta_after_dump__(o_dict)

        o_str = ''
        o_int = 0
        n_tabs = tabs + '  '
        o_key = ''
        d_value = None
        has_adorn = hasattr(obj, '__cotta_adorn__')

        if has_adorn:
            o_order = obj.__cotta_adorn__()
        else:
            o_order = list(o_dict.keys())
        o_last_index = len(o_order) - 1

        if nl:
            o_str += '\n'

        o_index = 0
        for o_key in o_order:

            if o_index:
                o_str += tabs

            if not o_key or o_key.isspace():
                pass
            elif dump_is_comment.findall(o_key):
                o_str += o_key
            else:
                d_value = o_dict[o_key]
                o_str += o_key + ': ' + _dump_obj(n_tabs, d_value, 1)

            if o_index < o_last_index:
                o_str += '\n'
            o_index += 1

        return o_str

    # custom dumper
    elif obj.__class__ in custom_dumpers:
        return _dump_obj(tabs, custom_dumpers[obj.__class__](obj), nl)

    # iterable
    elif hasattr(obj, '__iter__'):
        o_str = ''
        o_int = len(obj)
        o_last_index = o_int - 1
        n_tabs = tabs + '  '
        if nl:
            o_str += '\n' + tabs
        for o_index in range(o_int):
            if o_index:
                o_str += tabs
            o_str += '- ' + _dump_obj(n_tabs, obj[o_index], 0)
            if o_index < o_last_index:
                o_str += '\n'
        return o_str

    # else
    else:
        raise TypeNotSupported(obj.__class__)

cpdef dumps(obj):
    return _dump_obj('', obj, 0)

cpdef dump(obj, fileobj):
    fileobj.write(dumps(obj))

cpdef dump_to(obj, str location):
    body = dumps(obj)
    with open(location, 'w') as dump_file:
        dump_file.write(body)

cpdef redump_all():
    cdef YamlFile y_file
    for y_file in yaml_files.values():
        y_file.dump()

cpdef redump(obj):
    cdef YamlFile y_file
    if hasattr(obj, '__cotta__'):
        if obj.__cotta_file__ is not None:
            y_file = obj.__cotta_file__
            y_file.dump()

# load
cpdef _load_refresh(int reload, classobj, dict values):

    cdef CottaClassHead head

    if reload == 1:
        head = classobj.__cotta__

        if head.has_global_key:
            key = values.get(head.global_key)
            o_obj = head.get(key, key)
            head.from_data(o_obj, values)
            return o_obj

    return None

def _load(obj, y_file, int reload):

    # check if custom
    for loader in custom_loaders:
        get = loader(obj)
        if get is not custom_loader_fail:
            obj = get
            break

    # special
    if isinstance(obj, list):
        return [_load(item, y_file, reload) for item in obj]

    elif isinstance(obj, dict):

        n_dict = {
            _load(key, y_file, reload): _load(value, y_file, reload)
            for key, value in obj.items()
        }

        if 'class' in n_dict:
            o_class = class_objs[n_dict['class']]
            o_obj = _load_refresh(reload, o_class, n_dict)
            if o_obj is None:
                o_obj = o_class(init=False)
                init_new_obj(y_file, o_obj, n_dict, lambda: o_obj.__cotta__.from_data(o_obj, n_dict))
            return o_obj

        else:
            return n_dict

    else:
        return obj

cpdef _loads(text, y_file, int reload):
    output = _load(yaml.load(text, yaml.Loader), y_file, reload)
    return output

cpdef loads(text):
    return _loads(text, None, 0)

cpdef load(fileobj):
    y_file = get_yaml_file(fileobj.name)
    return _loads(fileobj.read(), y_file, 0)

cpdef _load_from(str filename, int reload):
    cdef YamlFile y_file
    y_file = get_yaml_file(filename)
    with open(filename, 'r') as load_file:
        y_file.item = _loads(load_file, y_file, reload)
        return y_file.item

cpdef load_from(str filename):
    return _load_from(filename, 0)

cdef _load_dir(str location, on_init=None):
    for filename in os.listdir(location):
        if os.path.isdir(location + '/' + filename):
            _load_dir(location + '/' + filename)
        else:
            if filename.endswith('.yaml'):
                load_from(location + '/' + filename)

cpdef load_dir(str location, on_init=None):

    # c vars
    cdef str filename
    cdef list all_items_old
    cdef list items = []

    # start
    global all_instances
    all_items_old = all_instances
    all_instances = items

    # load files
    _load_dir(location.replace('\\', '/'), on_init)

    # fill
    for item in items:
        item.__cotta__.fill(item)

    # initiate
    for inst in sorted(items, key=BatchInitSortFunction(items)):
        if hasattr(inst, '__cotta_on_batch_init__'):
            inst.__cotta_on_batch_init__(items)
            if on_init is not None:
                on_init(inst)

    # clean up
    all_instances = all_items_old
    all_instances.extend(items)

    # finished
    return items

