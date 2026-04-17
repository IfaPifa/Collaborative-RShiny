library(plumber)

#* @apiTitle Eco Deployment Calculator Backend (REST)

#* Calculate the sum of deployed sensors
#* @param num1
#* @param num2
#* @param sender
#* @post /calculate
#* @serializer unboxedJSON
function(num1 = 0, num2 = 0, sender = "unknown") {
  
  # 1. Plumber automatically extracts the JSON body into these function arguments!
  n1 <- as.numeric(num1)
  n2 <- as.numeric(num2)
  result <- n1 + n2
  
  # 2. Print to Docker logs for debugging
  print(paste("REST API Calculated:", n1, "+", n2, "=", result, "for", sender))
  
  # 3. Return a standard R list. The @serializer unboxedJSON decorator 
  # safely converts this into the exact JSON format Spring Boot expects.
  return(list(
    result = result,
    num1 = n1,
    num2 = n2,
    sender = sender,
    status = "success",
    timestamp = as.numeric(Sys.time())
  ))
}