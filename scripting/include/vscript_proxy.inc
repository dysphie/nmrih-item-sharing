#include <sdktools>

/* Runs a VScript function that returns a string
 * 
 * @param entity		Entity to run the function on
 * @param buffer		String buffer to store result
 * @param maxlen		Buffer size
 * @param format		VScript function to run
 * @param ...			VScript function format parameters
 * @return              Number of non-null bytes written.
 * @error Invalid entity. Failure to create VScript proxy.
 */
stock int RunEntVScriptString(int entity, char[] buffer, int maxlen, const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1) {
		ThrowError("Entity %d (%d) is invalid", index, entity);
	}

	char original[64];
	GetEntPropString(index, Prop_Data, "m_iName", original, sizeof(original));

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 5);
	Format(temp, sizeof(temp), "self.SetName(self.%s)", temp);

	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);

	int bytes = GetEntPropString(index, Prop_Data, "m_iName", buffer, maxlen);
	SetEntPropString(index, Prop_Data, "m_iName", original);
	return bytes;
}

/* Runs a VScript function that returns a float
 * 
 * @param entity		Entity to run the function on
 * @param format		VScript function to run
 * @param ...			VScript function format parameters
 * @return              VScript function return
 * @error Invalid entity. Failure to create VScript proxy. Non-float return
 */
stock float RunEntVScriptFloat(int entity, const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1) {
		ThrowError("Entity %d (%d) is invalid", index, entity);
	}

	char original[64];
	GetEntPropString(index, Prop_Data, "m_iName", original, sizeof(original));

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 3);
	Format(temp, sizeof(temp), "self.SetName(self.%s.tostring())", temp);

	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);

	int len = GetEntPropString(index, Prop_Data, "m_iName", temp, sizeof(temp));
	SetEntPropString(index, Prop_Data, "m_iName", original);

	if (len > 0)
	{
		float result;
		if (StringToFloatEx(temp, result) == len) {
			return result;
		}
	}

	ThrowError("Bad function return. Expected int, got \"%s\" (%d bytes)", temp, len);
	return 0.0;
}


/* Runs a VScript function that returns an int
 * 
 * @param entity		Entity to run the function on
 * @param format		VScript function to run
 * @param ...			VScript function format parameters
 * @return              VScript function return
 * @error Invalid entity. Failure to create VScript proxy. Non-bool return
 */
stock bool RunEntVScriptBool(int entity, const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1) {
		ThrowError("Entity %d (%d) is invalid", index, entity);
	}

	char original[64];
	GetEntPropString(index, Prop_Data, "m_iName", original, sizeof(original));

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 3);
	Format(temp, sizeof(temp), "self.SetName(self.%s.tointeger().tostring())", temp);

	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);

	int len = GetEntPropString(index, Prop_Data, "m_iName", temp, sizeof(temp));
	SetEntPropString(index, Prop_Data, "m_iName", original);

	if (len > 0)
	{
		int result;
		if (StringToIntEx(temp, result) == len) {
			return view_as<bool>(result);
		}
	}

	ThrowError("Bad function return. Expected int, got \"%s\" (%d bytes)", temp, len);
	return false;
}

/* Runs a VScript function that returns an int
 * 
 * @param entity		Entity to run the function on
 * @param format		VScript function to run
 * @param ...			VScript function format parameters
 * @return              VScript function return
 * @error Invalid entity. Failure to create VScript proxy. Non-int return
 */
stock int RunEntVScriptInt(int entity, const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1) {
		ThrowError("Entity %d (%d) is invalid", index, entity);
	}

	char original[64];
	GetEntPropString(index, Prop_Data, "m_iName", original, sizeof(original));

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 3);
	Format(temp, sizeof(temp), "self.SetName(self.%s.tostring())", temp);

	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);

	int len = GetEntPropString(index, Prop_Data, "m_iName", temp, sizeof(temp));
	SetEntPropString(index, Prop_Data, "m_iName", original);

	if (len > 0)
	{
		int result;
		if (StringToIntEx(temp, result) == len) {
			return result;
		}
	}

	ThrowError("Bad function return. Expected int, got \"%s\" (%d bytes)", temp, len);
	return 0;
}

/* Runs a VScript function with void return
 * 
 * @param entity		Entity to run the function on
 * @param format		VScript function to run
 * @param ...			VScript function format parameters 
 * @noreturn
 * @error Invalid entity. Failure to create VScript proxy. Non-int return
 */
stock void RunEntVScript(int entity, const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1) {
		ThrowError("Entity %d (%d) is invalid", index, entity);
	}

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 3);
	Format(temp, sizeof(temp), "self.%s", temp);

	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);
}

/* Runs a VScript function that returns a vector
 * 
 * @param entity		Entity to run the function on
 * @param format		VScript function to run
 * @param ...			VScript function format parameters 
 * @noreturn
 * @error Invalid entity. Failure to create VScript proxy. Non-vector return
 */
stock void RunEntVScriptVector(int entity, float vec[3], const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1) {
		ThrowError("Entity %d (%d) is invalid", index, entity);
	}

	char original[64];
	GetEntPropString(index, Prop_Data, "m_iName", original, sizeof(original));

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 4);
	Format(temp, sizeof(temp), "self.SetName(self.%s.ToKVString())", temp);
	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);

	GetEntPropString(index, Prop_Data, "m_iName", temp, sizeof(temp));
	SetEntPropString(index, Prop_Data, "m_iName", original);

	char strVec[3][11];
	ExplodeString(temp, " ", strVec, 3, sizeof(strVec[]));
	
	vec[0] = StringToFloat(strVec[0]);
	vec[1] = StringToFloat(strVec[1]);
	vec[2] = StringToFloat(strVec[2]);
}

/* Runs a VScript function that returns an entity
 * 
 * @param entity		Entity to run the code on
 * @param code			VScript code to run on the entity
 * @param proxy			logic_script_proxy entity. If invalid, one will be temporarily created
 * @return              VScript function return
 * @error 				Invalid entity. Failure to create VScript proxy
 */
stock int RunEntVScriptEnt(int entity, const char[] format, any ...)
{
	int index = EntRefToEntIndex(entity);
	if (index == -1)
		ThrowError("Entity %d (%d) is invalid", index, entity);

	char original[32];
	GetEntPropString(index, Prop_Data, "m_iName", original, sizeof(original));

	char temp[1024];
	VFormat(temp, sizeof(temp), format, 3);

	Format(temp, sizeof(temp),
		"local h = EntIndexToHScript(%d);" ...
		"local i = h.%s;" ...
		"h.SetName(i ? i.entindex().tostring() : \"\");",
		index, temp);
	
	SetVariantString(temp);
	AcceptEntityInput(index, "RunScriptCode", index, index);

	int result;

	char strResult[11];
	if (GetEntPropString(index, Prop_Data, "m_iName", strResult, sizeof(strResult))) {
		result = StringToInt(strResult);
	} else {
		result = -1;
	}

	SetEntPropString(index, Prop_Data, "m_iName", original);
	return result;
}