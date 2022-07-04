# Cotta
Cotta is a simple library used for mapping yaml files to objects.

### Installation
You can install cotta through pip like so
```commandline
pip install git+https://github.com/shaldokin/cotta.git
```

### Mapping a Class
```python
import cotta

@cotta.new_class()
class Person:
    name = cotta.Field()
    age = cotta.Field()

billy = Person(name='Billy', age=28)
print(cotta.dumps(billy))
```

The output would appear as so
```yaml
age: 28
class: person
name: Billy
```

You can also create a new object like so
```python
billy = cotta.new('person', name='Billy', age=28)
```

<br>

### Naming a Class
Cotta's uses kabob-casing for it's naming convention.
When you use `new_class` it will automatically set the name to the name of the class in kabob case.
You can set a different name however using the `name` parameter.

You can get the name of the class like so:
```python
print( Person.__cotta_name__ )
```
```
person
```

<br>

### Defining Field Types Using Converter Functions
Here is an example of wanting a datetime to be converted to a pandas timestamp on load
```python
import cotta
import pandas as pd

@cotta.new_class()
class Person:
    name = cotta.Field()
    dob = cotta.Field(conv=pd.Timestamp)
```
If you want to convert the value when saving, use the ```conv_to``` parameter
<br>

### Global Keys and References
When you declare a global key, all instances of that class are stored in a global dictionary for referencing.
You can declare a global key like so:
```python
@cotta.new_class(global_key='name')
class Person:
    name = cotta.Field()
    age = cotta.Field()
```

This allows other objects to save the global key instead of the entire object.
You can use the global key as a reference like so:
```python
@cotta.new_class(global_key='name')
class Person:
    name = cotta.Field()
    age = cotta.Field()
    friend = cotta.Field(kind='refr', refr_class='person')
```
<br>

And so this:
```python
billy = Person(name='Billy', age=28)
jackie = Person(name='Jackie', age=34, friend=billy)

print(cotta.dumps(jackie))
```

Would output this
```yaml
age: 34
class: person
friend: billy
name: Jackie
```
<br>

Just make sure to have all referenced objects exported too, or created so when trying to access it can find it.
Referencing attributes use lazy accessing, so you can create the object oon startup, as long as it's before getting the attribute from the object.

You can make a list of references too like so
```python
@cotta.new_class(global_key='name')
class Person:
    name = cotta.Field()
    age = cotta.Field()
    friends = cotta.Field(kind='refr-list', refr_class='person')
```

If an object has a global key, you can access all of the instances like this
```python
Person.__cotta_instances__
```

You can get an object by its global key like so
```python
cotta.get('person', 'billy')
```
<br>

### Using A Strict Single Class
If you want a field to be a strict single class, or a list of single classes, this can allow you to not need the "class" attribute, which can be less tedious in a long list of objects.
You can do so like this
```python
import cotta

@cotta.new_class()
class Pet:
    name = cotta.Field()
    type = cotta.Field()

@cotta.new_class(global_key='name')
class Person:
    name = cotta.Field()
    age = cotta.Field()
    pet = cotta.Field(kind='single', refr_class='person')
```

An appropriate yaml that would work for this
```yaml
class: person
name: Jason
age: 23
pet:
  name: Spot
  type: dog
```

The class of `pet` is known to be a Pet and so the `class` does not need specified.
The same thing can be done for a list by specifying the `kind` attribute of the field as `single-list`.

```yaml
class: person
name: Jason
age: 23
pets:
  - name: Spot
    type: dog
  - name: Lucky
    type: dog
```

<br>

### Special Attributes
A special field will allow you to set a custom loader and dumper.

```python
import cotta

@cotta.new_class(global_key='name')
class Person:
    
    name = cotta.Field()
    age = cotta.Field()
    nickname = cotta.Field(kind='special')
    
    @nickname.special_to
    def nickname_to(self, data):
        if self.nickname is None:
            data['nickname'] = self.name
        else:
            data['nickname'] = self.nickname
            
    @nickname.special_from
    def nickname_from(self, data):
        if 'nickname' not in data:
            self.nickname = self.name
        else:
            self.nickname = data.get('nickname')
```

<br>

### Initiating Functionality
You can set functionality for immediately after a new instance is created, and before it is created, like so.

```python
import cotta

@cotta.new_class(global_key='name')
class Person:
    
    name = cotta.Field()
    age = cotta.Field()
    nickname = cotta.Field()

    def __cotta_before_init__(self, data):
        pass
    
    def __cotta_after_init__(self):
        if self.nickname is None:
            self.nickname = self.name

```

### DateTime
Datetime objects are supported and can be implemented like so

```python
import cotta

@cotta.new_class(global_key='name')
class Person:
    name = cotta.Field()
    dob = cotta.Field()
```

```yaml
class: person
name: Erica
dob: 1993-11-23 00:00:00
```
You can add/remove `strptime` formats to the conversion function by modifying `cotta.datetime_formats` which is simply a list of formats.
You can completely change the datetime conversion function all together by setting the variable `cotta.to_datetime_func`.

<br>

### Timedeltas
Timedeltas are also supported as strings and appear like so
```
30secs
2hours 3mins
7 weeks 4 days
```
The supported fields are:
* `weeks` or `wks`
* `days`
* `hours` or `hrs`
* `minutes` or `mins`
* `seconds` or `secs`
* `milliseconds` or `millis`
* `microseconds` or `micros`

<br>

### Custom Loaders and Dumpers
Just like Timedeltas and Datetimes, you can dump and class like so

```python
import cotta
import pandas as pd

@cotta.custom_dumper(pd.Timestamp)
def timestamp_dumper(obj):
    return 'ts' + str(obj)

@cotta.custom_loader
def timestamp_loader(obj):
    if isinstance(obj, str):
        if obj.startswith('ts'):
            return pd.Timestamp(obj[2:])
    return cotta.custom_loader_fail
```

Every single value will run through the custom loader, so it is important to check the value and only return if it matches whatever you are looking for.
If it does not match, you must return the `cotta.custom_loader_fail` singleton, otherwise the value will be set to `None`.

<br>

### Refreshing an Object
Any object loaded from a yaml file, will have it's file tracked.
If any changes are made to the file, you can refresh the object like so:
```python
cotta.refresh(obj)
```
You can refresh all objects by omitting any parameters.

<br>

### Loading a directory

```python
cotta.load_dir('.')
```

This will load all yaml files in a directory, and recursively in subdirectories.
When doing so, if the yaml classes, have a `__cotta_batch_init__` method, it will be called after all objects are loaded.

```python
def __cotta_batch_init__(self, items):
    pass
```

You can also change the order that an item is sorted during the batch initiation process like so
```python
def __cotta_batch_init_sort__(self, items):
    return items.index(self)
```
