component hint="I am the testing Bean Factory" output="false" persistent="false" {

	/**
	* @hint "I am the constructor"
	* @output false
	**/
	public component function init() {
		variables.ProductService = new ProductService();
		variables.ErrorLogger = new ErrorLogger();
		return this;
	}
	
	/**
	* @hint "I get beans"
	* @output false
	**/
	public component function getBean( string BeanName ) {
		return variables[arguments.BeanName];
	}

}