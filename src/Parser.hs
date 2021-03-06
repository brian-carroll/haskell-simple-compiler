module Parser (readExpr, readMaybeExpr, readExprList) where

-- Libraries
import Text.ParserCombinators.Parsec (Parser, (<|>), parse,
            many, many1, noneOf, oneOf, endBy, sepBy, skipMany1, try, unexpected, optionMaybe, optional,
            anyChar, char, digit, letter, space)
import Control.Monad.Error (throwError, liftM, when)
import Numeric (readOct, readHex)
import qualified Data.Char

-- Local modules
import LispTypes (LispVal (..), LispError (..), ThrowsError)



-- -----------
-- RUN PARSERS
-- -----------
readOrThrow :: Parser a -> String -> ThrowsError a
readOrThrow parser input =
    case parse parser "lisp" input of
        Left err  -> throwError $ Parser err
        Right val -> return val


readExpr :: String -> ThrowsError LispVal
readExpr = readOrThrow parseExpr


readMaybeExpr :: String -> ThrowsError (Maybe LispVal)
readMaybeExpr = readOrThrow parseMaybeExpr


readExprList :: String -> ThrowsError [LispVal]
readExprList = readOrThrow parseExprList


-- ------------------
-- HIGH LEVEL PARSERS
-- ------------------
parseMaybeExpr :: Parser (Maybe LispVal)
parseMaybeExpr =
    do
        optional spacesOrComments
        optionMaybe parseExpr   -- REPL input could be a blank line


parseExprList :: Parser [LispVal]
parseExprList =
    do
        optional spacesOrComments
        endBy parseExpr spacesOrComments


parseExpr :: Parser LispVal
parseExpr =
    parseString
    <|> (try parseCharacter)
    <|> (try parseNumber)
    <|> parseAtom
    <|> parseQuoted
    <|> do
            char '('
            x <- try parseList <|> parseDottedList
            char ')'
            return x


parseList :: Parser LispVal
parseList =
    liftM List $ sepBy parseExpr spacesOrComments


parseDottedList :: Parser LispVal
parseDottedList = do
    head <- endBy parseExpr spacesOrComments
    tail <- char '.' >> spacesOrComments >> parseExpr
    return $ DottedList head tail


parseQuoted :: Parser LispVal
parseQuoted = do
    char '\''
    x <- parseExpr
    return $ List [Atom "quote", x]


parseString :: Parser LispVal
parseString =
    do
        char '"'
        x <- many (escapedChar <|> (noneOf "\""))
        char '"'
        return $ String x


parseCharacter :: Parser LispVal
parseCharacter =
    do
        char '#'
        char '\\'
        c <- (try characterName <|> anyChar)
        return $ Character c


parseAtom :: Parser LispVal
parseAtom =
    do
        first <- letter <|> symbol
        rest <- many (letter <|> digit <|> symbol)
        let atom = first:rest
        return $
            case atom of
                "#t" -> Bool True
                "#f" -> Bool False
                _    -> Atom atom


parseNumber :: Parser LispVal
parseNumber =
    do
        value <- (radixNumber <|> plainNumber)
        return $ Number value


-- ------------------
-- LOW-LEVEL PARSING
-- ------------------

symbol :: Parser Char
symbol =
    oneOf "!#$%&|*+-/:<=>?@^_~"


-- Comment: Transform everything from ';' to '\n' into a space
-- This keeps Haskell type checker happy (whereas returning '()' doesn't)
comment :: Parser Char
comment =
    do
        char ';'
        many (noneOf "\n")
        return ' '


spacesOrComments :: Parser ()
spacesOrComments =
    skipMany1 (space <|> comment)


escapedChar :: Parser Char
escapedChar =
    do
        char '\\'
        x <- oneOf "tnr\"\\"
        return $
            case x of
                '"' -> '"'
                '\\' -> '\\'
                't' -> '\t'
                'n' -> '\n'
                'r' -> '\r'
                _ -> undefined


plainNumber :: Parser Integer
plainNumber =
    do
        numStr <- many1 digit
        let value = read numStr
        return value


radixNumber :: Parser Integer
radixNumber =
    do
        char '#'
        value <- (hexNumber <|> octalNumber <|> decimalNumber <|> binaryNumber)
        return value


hexNumber :: Parser Integer
hexNumber =
    do
        oneOf "Xx"
        numStr <- many1 $ oneOf "0123456789abcdefABCDEF"
        let [(value, _)] = readHex numStr
        return value


octalNumber :: Parser Integer
octalNumber =
    do
        oneOf "Oo"
        numStr <- many1 $ oneOf "01234567"
        let [(value, _)] = readOct numStr
        return value


decimalNumber :: Parser Integer
decimalNumber =
    do
        oneOf "Dd"
        numStr <- many1 $ digit
        let value = read numStr
        return value


binaryNumber :: Parser Integer
binaryNumber =
    do
        oneOf "Bb"
        numStr <- many1 $ oneOf "01"
        let value = readBin numStr
        return value


readBin :: String -> Integer
readBin str =
    let
        (value, _) = foldr readBinHelp (0,1) str
    in
        value


readBinHelp :: Char -> (Integer, Integer) -> (Integer, Integer)
readBinHelp char (acc, bitWeight) =
    let
        bitValue =
            if char == '1' then
                bitWeight
            else
                0
    in
        ( acc+bitValue, 2*bitWeight )


characterName :: Parser Char
characterName =
    do
        first <- letter
        rest <- many1 $ letter
        let name = map Data.Char.toLower (first:rest)

        -- http://sicp.ai.mit.edu/Fall-2003/manuals/scheme-7.5.5/doc/scheme_6.html
        let c = case name of
                    "altmode" -> '\ESC'
                    "backnext" -> '\US'
                    "backspace" -> '\BS'
                    "call" -> '\SUB'
                    "linefeed" -> '\LF'
                    "newline" -> '\LF'
                    "page" -> '\FF'
                    "return" -> '\CR'
                    "rubout" -> '\DEL'
                    "tab" -> '\HT'
                    "space" -> ' '
                    _ -> '_'

        when (c=='_') (unexpected ("character name '" ++ name ++ "'"))
        return c
