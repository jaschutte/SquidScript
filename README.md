# SquidScript
A language, designed for Splatoon fans!

All the code you need to run SquidScript files is in `main.lua`.  
Two example projects are included, `fib.sqs` and `pong.sqs`.  
The pong example will only work for systems with `stty` installed. Most unix systems will have this pre-installed already.

# How to run SquidScript
First you have to download Lua 5.4, the download can be found [here](https://www.lua.org/download.html)  

After having done that, download the `main.lua` and `fib.sqs` file found in this repository and open a terminal.  
In the terminal, enter the following:  
`lua main.lua -i fib.sqs`  
It will wait for you to input a number, type in 5 and it will calculate the first 5 fibonacci numbers!  

The more general usecase would be: `lua main.lua -i <squidscriptcode.sqs>`, where `<squidscriptcode.sqs>` would be substited by the name of your own code file.  

For more usage, check out the help `lua main.lua -h`.
