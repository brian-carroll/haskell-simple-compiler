module Main where

-- Libraries
import System.Environment (getArgs)
import System.IO (hFlush, hPutStrLn, stdout)
import Control.Monad (liftM)


-- Local modules
import Parser (readExpr)
import Eval (eval, primitiveBindings, Env, runIOThrows, liftThrows, bindVars)
import LispTypes (LispVal (..))


-- ----
-- MAIN
-- ----
main :: IO ()
main = do
    args <- getArgs
    case args of
        [] ->
            runRepl

        -- If first command line arg starts with '(' then assume it's a Lisp expression
        (('(' : _) : _) ->
            runOne $ args !! 0

        -- Otherwise assume it's a filename
        _ ->
            runFile args


-- Evaluate and print one expression
runOne :: String -> IO ()
runOne expr =
    primitiveBindings >>= flip evalAndPrint expr


-- Read a Scheme file and execute it
runFile :: [String] -> IO ()
runFile args =
    let
        firstArgLispVal =
            String (args !! 0)
        otherArgsLispVal =
            List $ map String $ drop 1 args
        loadCommandLisp =
            List [Atom "load", firstArgLispVal]
    in do
        env <- primitiveBindings >>= flip bindVars [("args", otherArgsLispVal)] 
        (runIOThrows $ liftM show $ eval env loadCommandLisp)
            >>= hPutStrLn stdout


-- Apply (evalAndPrint env) to each line of input ('env' is passed in via >>=)
runRepl :: IO ()
runRepl =
    primitiveBindings >>= until_ (== "quit") (readPrompt "Lisp>>> ") . evalAndPrint


-- -----
-- REPL
-- -----
flushStr :: String -> IO ()
flushStr str =
    putStr str >> hFlush stdout


readPrompt :: String -> IO String
readPrompt prompt =
    flushStr prompt >> getLine


evalString :: Env -> String -> IO String
evalString env expr =
    runIOThrows $   -- Convert IOThrowsError action into IO action
    liftM show $    -- Convert evaluated result to a string, within IOThrowsError
    (liftThrows $ readExpr expr) >>= eval env  -- Lift readExpr from ThrowsError into IOThrowsError, then evaluate


evalAndPrint :: Env -> String -> IO ()
evalAndPrint env expr =
    evalString env expr >>= putStrLn


until_ :: Monad m => (a -> Bool) -> m a -> (a -> m ()) -> m ()
until_ pred prompt action = do
   result <- prompt
   if pred result
      then return ()
      else action result >> until_ pred prompt action
