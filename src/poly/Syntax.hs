module Syntax where

import Types
import Loc
import Basic
import qualified Data.Foldable
{-
 - Concrete syntax tree for the surface language.
 - Expressions are polymorphic to include extra information,
 - which will vary depending on the context.
 -}

-- Description of constants and variables.
data Const a = Const a String -- info and name 
    deriving Functor

data Var a = Var a String -- named variable
           | AnonVar a    -- wildcard
    deriving Functor

{-
 - The syntactic structures are organized recursively from in
 - inclusion order
 -}

-- Any sentence of the program
data SSent a = SSent_clause a (SClause  a)
             | SSent_goal   a (SGoal    a)
             | SSent_comm   a (SCommand a)
    deriving Functor

-- A goal sentence
data SGoal a = SGoal a (SExpr a)
    deriving Functor

-- A directive
data SCommand a = SCommand a (SExpr a)
    deriving Functor

-- A clause. Nothing in the body represents a fact, Just a rule.
data SClause a = SClause { clInfo :: a 
                         , clHead :: SHead a
                         , clBody :: Maybe (SGets, SExpr a)
                         }
    deriving Functor

-- Monomorphic or polymorphic gets
-- TODO implement polymorphic
data SGets = SGets_mono | SGets_poly 

-- Clause head
data SHead a = SHead { headInfo :: a        -- Info
                     , headName :: Const a  -- clause name 
                     , headGivenAr :: Maybe Int 
                                -- optional GIVEN arity 
                     , headInfAr :: Int  -- inferred arity
                     , headArgs  :: [[SExpr a]] -- Arguments
                     }
    deriving Functor

-- Expressions 
data SExpr a = SExpr_paren   a (SExpr a)  -- in Parens    
             | SExpr_const   a            -- constant 
                             (Const a)    -- id
                             Bool         -- interpreted as predicate?
                             (Maybe Int)  -- optional GIVEN arity 
                             Int          -- INFERRED arity
             | SExpr_var     a (Var a)    -- variable
             | SExpr_number  a (Either Integer Double)
                                          -- numeric constant
             | SExpr_predCon a            -- predicate constant
                             (Const a)    -- id
                             (Maybe Int)  -- optional GIVEN arity
                             Int          -- INFERRED arity
             | SExpr_app  a (SExpr a) [SExpr a]  -- application
             | SExpr_op   a          -- operator
                          (Const a)  -- id
                          Bool       -- interpreted as pred?         
                          [SExpr a]  -- arguments
             | SExpr_lam  a [Var a] (SExpr a)    -- lambda abstr.
             | SExpr_list a [SExpr a] (Maybe (SExpr a))
                          -- list: initial elements, maybe tail
             | SExpr_eq   a (SExpr a) (SExpr a)  -- unification
             | SExpr_ann  a (SExpr a) Type       -- type annotated
    deriving Functor


-- The following types represent the organization used
-- by the type checker

-- All clauses defining a predicate
data SPredDef a = SPredDef { predDefName    :: String 
                           , predDefArity   :: Int
                           , predDefClauses :: [SClause a]
                           } 

-- A dependency group
type SDepGroup a = [SPredDef a]

-- All predicate definitions, organized into dependency groups in DAG order
type SDepGroupDag a = [SDepGroup a]

-- A constant as it is saved in a type environment
type PredConst = (String, Int)



{- 
 - Utility functions for the syntax tree of polyHOPES
 -}

-- Print syntax tree
-- TODO make them better
deriving instance Show a => Show (Const a)
deriving instance Show a => Show (Var a)
deriving instance Show a => Show (SClause a)
deriving instance           Show SGets
deriving instance Show a => Show (SHead a)
deriving instance Show a => Show (SExpr a)
deriving instance Show a => Show (SGoal a)
deriving instance Show a => Show (SCommand a)
deriving instance Show a => Show (SSent a)


-- Head

instance HasName (SHead a) where 
    nameOf = nameOf.headName
instance HasArity (SHead a) where
    arity h = case headGivenAr h of 
        Just n  -> Just n
        Nothing -> Just $ headInfAr h

-- PredDef

instance HasName (SPredDef a) where 
    nameOf = predDefName
instance HasArity (SPredDef a) where
    arity = Just . predDefArity

-- Clause
instance HasName (SClause a) where 
    nameOf = nameOf.clHead
instance HasArity (SClause a) where
    arity = arity.clHead


-- Simple predicates on sentences
isGoal (SSent_goal _ _) = True
isGoal _ = False 

isClause (SSent_clause _ _) = True 
isClause _ = False

isCommand (SSent_comm _ _) = True
isCommand _ = False

isFact :: SClause a -> Bool
isFact (SClause _ _ Nothing) = True
isFact _ = False



-- Filter everything that can be a predicate constant
isPredConst (SExpr_predCon _ _ _ _) = True
isPredConst (SExpr_const _ _ predStatus _ _) = predStatus
isPredConst (SExpr_op  _ _ predStatus _) = predStatus 
isPredConst _ = False

-- Finds arity of a constant expression
instance HasArity (SExpr a) where 
    arity (SExpr_paren _ ex) = arity ex
    arity (SExpr_const _ _ _ given inferred) =
        case given of 
            Just n  -> Just n 
            Nothing -> Just inferred
    arity ( SExpr_predCon _ _ given inferred) =
        case given of 
            Just n  -> Just n 
            Nothing -> Just inferred
    arity (SExpr_op _ _ _ args) = Just $ length args      
    arity (SExpr_ann _ ex _) = arity ex
    arity _ = Nothing

instance HasName (Const a) where
    nameOf (Const _ nm) = nm 

instance HasName (SExpr a) where 
    nameOf (SExpr_paren _ ex) = nameOf ex
    nameOf (SExpr_const _ c _ _ _) = nameOf c
    nameOf (SExpr_predCon _ c _ _) = nameOf c
    nameOf (SExpr_op _ op _ _)  = nameOf op
    nameOf _ = ""

-- Get a list of all subexpressions contained in an expression
instance Flatable (SExpr a) where
    flatten ex@(SExpr_paren a ex') = ex : flatten ex'
    flatten ex@(SExpr_app _ func args) =
        ex : func : ( concat $ map flatten args)
    flatten ex@(SExpr_op _ _ _ args) =
        ex : (concat $ map flatten args)
    flatten ex@(SExpr_lam _ vars bd) =
        ex : (map varToExpr vars) ++ (flatten bd)
        where varToExpr v@(Var a s)   = SExpr_var a v
              varToExpr v@(AnonVar a) = SExpr_var a v
    flatten ex@(SExpr_list _ initEls tl) =
        ex : ( concat $ map flatten initEls) ++ 
            (case tl of 
                 Nothing -> [] 
                 Just ex -> flatten ex
            )
    flatten ex@(SExpr_eq _ ex1 ex2) =
        ex : (flatten ex1) ++ (flatten ex2)
    flatten ex@(SExpr_ann _ ex' _) =
        ex : (flatten ex')
    flatten ex = [ex]  -- nothing else has subexpressions




{-
-- Syntax constructs have types if it exists in the 
-- information they carry
-- Maybe useful later
instance HasType a => HasType (Const a) where
    typeOf (Const a _ _) = typeOf a
    hasType tp (Const a s i) = Const (hasType tp a) s i

instance HasType a => HasType (Var a) where
    typeOf (Var a _)   = typeOf a
    typeOf (AnonVar a) = typeOf a
    hasType tp (Var a s)   = Var (hasType tp a) s
    hasType tp (AnonVar a) = AnonVar (hasType tp a)
-- FIXME : complete these!
instance HasType a => HasType (SClause a) where
    typeOf (SClause a _ _ _) = typeOf a 
    --hasType tp (SClause a _ _ _) = hasType tp a

instance HasType a => HasType (SHead a) where
    typeOf (SHead a _ _) = typeOf a
    --hasType tp (SHead a _ _) = hasType tp a

instance HasType a => HasType (SBody a) where
    typeOf (SBody_par a _ )     = typeOf a
    typeOf (SBody_pop a _ _ _ ) = typeOf a
    typeOf (SBody_pe  a _ )     = typeOf a
    --hasType tp (SBody_par a _ )     = hasType tp a
    --hasType tp (SBody_pop a _ _ _ ) = hasType tp a
   -- hasType tp (SBody_pe  a _ )     = hasType tp a

instance HasType a => HasType (SOp a) where
    typeOf (SAnd a) = typeOf a
    typeOf (SOr  a) = typeOf a
    typeOf (SFollows a) = typeOf a
  --  hasType tp (SAnd a) = hasType tp a
   -- hasType tp (SOr  a) = hasType tp a
  --  hasType tp (SFollows a) = hasType tp a

instance HasType a => HasType (SExpr a) where
    typeOf (SExpr a _ _ ) = typeOf a
  --  hasType tp (SExpr a _ _ ) = hasType tp a

instance HasType a => HasType (SGoal a) where
    typeOf (SGoal a ) = typeOf a
  --  hasType tp (SGoal a) = hasType tp a

-- Syntax constructs have location if it exists in the 
-- information they carry
-- Maybe useful later
instance HasLocation a => HasLocation (Const a) where
    loc (Const a _ _) = loc a
    
instance HasLocation a => HasLocation (Var a) where
    loc (Var a _)   = loc a
    loc (AnonVar a) = loc a

instance HasLocation a => HasLocation (SClause a) where
    loc (SClause a _ _ _) = loc a

instance HasLocation a => HasLocation (SHead a) where
    loc (SHead a _ _) = loc a

instance HasLocation a => HasLocation (SBody a) where
    loc (SBody_par a _ )     = loc a
    loc (SBody_pop a _ _ _ ) = loc a
    loc (SBody_pe  a _ )     = loc a

instance HasLocation a => HasLocation (SOp a) where
    loc (SAnd a) = loc a
    loc (SOr  a) = loc a
    loc (SFollows a) = loc a

instance HasLocation a => HasLocation (SExpr a) where
    loc (SExpr a _ _ ) = loc a

instance HasLocation a => HasLocation (SGoal a) where
    loc (SGoal a) = loc a
-}

-- true and fail constants

sTrue :: SExpr ()
sTrue =  SExpr_const () 
                     (Const () "true")  
                     True
                     Nothing
                     (-1)
sFail :: SExpr ()
sFail =  SExpr_const () 
                     (Const () "fail")  
                     True
                     Nothing
                     (-1)

sCut :: SExpr ()
sCut =  SExpr_const () 
                    (Const () "!")  
                    True
                    Nothing
                    (-1)

sNil :: SExpr ()
sNil = SExpr_const () 
                   (Const () "[]")  
                   False
                   Nothing
                   (-1)
