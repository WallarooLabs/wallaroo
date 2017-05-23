#ifdef __APPLE__
    #include <Python/Python.h>
#else
    #include <python2.7/Python.h>
#endif

PyObject *g_user_deserialization_fn;
PyObject *g_user_serialization_fn;

extern PyObject *load_module(char *module_name)
{
  PyObject *pName, *pModule;

  pName = PyString_FromString(module_name);
  /* Error checking of pName left out */

  pModule = PyImport_Import(pName);
  Py_DECREF(pName);

  return pModule;
}

extern PyObject *application_setup(PyObject *pModule, PyObject *args)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(pModule, "application_setup");
  pValue = PyObject_CallFunctionObjArgs(pFunc, args, NULL);
  Py_DECREF(pFunc);

  return pValue;
}

extern size_t list_item_count(PyObject *list)
{
  return PyList_Size(list);
}

extern PyObject *get_application_setup_item(PyObject *list, size_t idx)
{
  return PyList_GetItem(list, idx);
}

extern char *get_application_setup_action(PyObject *item)
{
  PyObject *action = PyTuple_GetItem(item, 0);
  char * rtn = PyString_AsString(action);
  Py_DECREF(action);
  return rtn;
}

extern size_t source_decoder_header_length(PyObject *source_decoder)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(source_decoder, "header_length");
  pValue = PyObject_CallFunctionObjArgs(pFunc, NULL);
  Py_DECREF(pFunc);

  size_t sz = PyInt_AsSsize_t(pValue);
  Py_DECREF(pValue);
  return sz;
}

extern size_t source_decoder_payload_length(PyObject *source_decoder, char *bytes, size_t size)
{
  PyObject *pFunc, *pValue, *pBytes;

  pFunc = PyObject_GetAttrString(source_decoder, "payload_length");
  pBytes = PyBytes_FromStringAndSize(bytes, size);
  pValue = PyObject_CallFunctionObjArgs(pFunc, pBytes, NULL);

  size_t sz = PyInt_AsSsize_t(pValue);

  Py_DECREF(pFunc);
  Py_DECREF(pBytes);
  Py_DECREF(pValue);

  return sz;
}

extern PyObject *source_decoder_decode(PyObject *source_decoder, char *bytes, size_t size)
{
  PyObject *pFunc, *pBytes, *pValue;

  pFunc = PyObject_GetAttrString(source_decoder, "decode");
  pBytes = PyBytes_FromStringAndSize(bytes, size);
  pValue = PyObject_CallFunctionObjArgs(pFunc, pBytes, NULL);

  Py_DECREF(pFunc);
  Py_DECREF(pBytes);

  return pValue;
}

extern PyObject *instantiate_python_class(PyObject *class)
{
  return PyObject_CallFunctionObjArgs(class, NULL);
}

extern PyObject *get_name(PyObject *pObject)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(pObject, "name");
  pValue = PyObject_CallFunctionObjArgs(pFunc, NULL);

  Py_DECREF(pFunc);

  return pValue;
}

extern PyObject *computation_compute(PyObject *computation, PyObject *data)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(computation, "compute");
  pValue = PyObject_CallFunctionObjArgs(pFunc, data, NULL);
  Py_DECREF(pFunc);

  if (pValue != Py_None)
    return pValue;
  else
    return NULL;
}

extern PyObject *sink_encoder_encode(PyObject *sink_encoder, PyObject *data)
{
  PyObject *pFunc, *pArgs, *pValue;

  pFunc = PyObject_GetAttrString(sink_encoder, "encode");
  pValue = PyObject_CallFunctionObjArgs(pFunc, data, NULL);
  Py_DECREF(pFunc);

  return pValue;
}

extern void py_incref(PyObject *o)
{
  Py_INCREF(o);
}

extern void py_decref(PyObject *o)
{
  Py_DECREF(o);
}

extern PyObject *state_builder_build_state(PyObject *state_builder)
{
  PyObject *pFunc, *pArgs, *pValue;

  pFunc = PyObject_GetAttrString(state_builder, "build");
  pValue = PyObject_CallFunctionObjArgs(pFunc, NULL);
  Py_DECREF(pFunc);

  return pValue;
}

extern PyObject *stateful_computation_compute(PyObject *computation, PyObject *data, PyObject *state)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(computation, "compute");
  pValue = PyObject_CallFunctionObjArgs(pFunc, data, state, NULL);
  Py_DECREF(pFunc);

  return pValue;
}

extern long key_hash(PyObject *key)
{
  return PyObject_Hash(key);
}


extern int key_eq(PyObject *key, PyObject* other)
{
  return PyObject_RichCompareBool(key, other, Py_EQ);
}

extern PyObject *partition_function_partition(PyObject *partition_function, PyObject *data)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(partition_function, "partition");
  pValue = PyObject_CallFunctionObjArgs(pFunc, data, NULL);
  Py_DECREF(pFunc);

  return pValue;
}

extern long partition_function_partition_u64(PyObject *partition_function, PyObject *data)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(partition_function, "partition");
  pValue = PyObject_CallFunctionObjArgs(pFunc, data, NULL);
  Py_DECREF(pFunc);

  long rtn = PyInt_AsLong(pValue);
  Py_DECREF(pValue);
  return rtn;
}

extern void set_user_serialization_fns(PyObject *module)
{
  if (PyObject_HasAttrString(module, "deserialize") && PyObject_HasAttrString(module, "serialize"))
  {
    g_user_deserialization_fn = PyObject_GetAttrString(module, "deserialize");
    g_user_serialization_fn = PyObject_GetAttrString(module, "serialize");
  }
  else
  {
    PyObject *wallaroo = PyObject_GetAttrString(module, "wallaroo");
    g_user_deserialization_fn = PyObject_GetAttrString(wallaroo, "deserialize");
    g_user_serialization_fn = PyObject_GetAttrString(wallaroo, "serialize");
    Py_DECREF(wallaroo);
  }
}

extern void *user_deserialization(char *bytes)
{
  unsigned char *ubytes = (unsigned char *)bytes;
  // extract size
  size_t size = (((size_t)ubytes[0]) << 24)
    + (((size_t)ubytes[1]) << 16)
    + (((size_t)ubytes[2]) << 8)
    + ((size_t)ubytes[3]);

  PyObject *py_bytes = PyBytes_FromStringAndSize(bytes + 4, size);
  PyObject *ret = PyObject_CallFunctionObjArgs(g_user_deserialization_fn, py_bytes, NULL);

  Py_DECREF(py_bytes);

  return ret;
}

extern size_t user_serialization_get_size(PyObject *o)
{
  PyObject *user_bytes = PyObject_CallFunctionObjArgs(g_user_serialization_fn, o, NULL);
  size_t size = PyString_Size(user_bytes);
  Py_DECREF(user_bytes);

  // return the size of the buffer plus the 4 bytes needed to record that size.
  return 4 + size;
}

extern void user_serialization(PyObject *o, char *bytes)
{
  PyObject *user_bytes = PyObject_CallFunctionObjArgs(g_user_serialization_fn, o, NULL);

  size_t size = PyString_Size(user_bytes);

  unsigned char *ubytes = (unsigned char *) bytes;

  ubytes[0] = (unsigned char)(size >> 24);
  ubytes[1] = (unsigned char)(size >> 16);
  ubytes[2] = (unsigned char)(size >> 8);
  ubytes[3] = (unsigned char)(size);

  memcpy(bytes + 4, PyString_AsString(user_bytes), size);

  Py_DECREF(user_bytes);
}

extern int py_bool_check(PyObject *b)
{
  return PyBool_Check(b);
}

extern int is_py_none(PyObject *o)
{
  return o == Py_None;
}
