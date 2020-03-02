def distri = binding.getVariables().get("distribution")
if (distri == null) {
	return "master" // for the parent job
} else {
	return "slave:${distri}".toString()
}