%
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

\section[RdrName]{@RdrName@}

\begin{code}
module RdrName (
	RdrName(..),	-- Constructors exported only to BinIface

	-- Construction
	mkRdrUnqual, mkRdrQual, 
	mkUnqual, mkVarUnqual, mkQual, mkOrig,
	nameRdrName, getRdrName, 
	mkDerivedRdrName, 

	-- Destruction
	rdrNameModule, rdrNameOcc, setRdrNameSpace,
	isRdrDataCon, isRdrTyVar, isRdrTc, isQual, isUnqual, 
	isOrig, isOrig_maybe, isExact, isExact_maybe, isSrcRdrName,

	-- Printing;	instance Outputable RdrName

	-- LocalRdrEnv
	LocalRdrEnv, emptyLocalRdrEnv, extendLocalRdrEnv,
	lookupLocalRdrEnv, elemLocalRdrEnv,

	-- GlobalRdrEnv
	GlobalRdrEnv, emptyGlobalRdrEnv, mkGlobalRdrEnv, plusGlobalRdrEnv, 
	lookupGlobalRdrEnv, extendGlobalRdrEnv,
	pprGlobalRdrEnv, globalRdrEnvElts,
	lookupGRE_RdrName, lookupGRE_Name,

	-- GlobalRdrElt, Provenance, ImportSpec
	GlobalRdrElt(..), isLocalGRE, unQualOK, 
	Provenance(..), pprNameProvenance,
	ImportSpec(..), ImpDeclSpec(..), ImpItemSpec(..), 
	importSpecLoc, importSpecModule
  ) where 

#include "HsVersions.h"

import OccName	( NameSpace, varName,
		  OccName, UserFS, 
		  setOccNameSpace,
		  mkOccFS, occNameFlavour,
		  isDataOcc, isTvOcc, isTcOcc,
		  OccEnv, emptyOccEnv, extendOccEnvList, lookupOccEnv, 
		  elemOccEnv, plusOccEnv_C, extendOccEnv_C, foldOccEnv,
		  occEnvElts
		)
import Module   ( Module, mkModuleFS )
import Name	( Name, NamedThing(getName), nameModule, nameParent_maybe,
		  nameOccName, isExternalName, nameSrcLoc )
import Maybes	( mapCatMaybes )
import SrcLoc	( isGoodSrcLoc, SrcSpan )
import Outputable
import Util	( thenCmp )
\end{code}


%************************************************************************
%*									*
\subsection{The main data type}
%*									*
%************************************************************************

\begin{code}
data RdrName 
  = Unqual OccName
	-- Used for ordinary, unqualified occurrences 

  | Qual Module OccName
	-- A qualified name written by the user in 
	--  *source* code.  The module isn't necessarily 
	-- the module where the thing is defined; 
	-- just the one from which it is imported

  | Orig Module OccName
	-- An original name; the module is the *defining* module.
	-- This is used when GHC generates code that will be fed
	-- into the renamer (e.g. from deriving clauses), but where
	-- we want to say "Use Prelude.map dammit".  
 
  | Exact Name
	-- We know exactly the Name. This is used 
	--  (a) when the parser parses built-in syntax like "[]" 
	--	and "(,)", but wants a RdrName from it
	--  (b) when converting names to the RdrNames in IfaceTypes
	--	Here an Exact RdrName always contains an External Name
	--	(Internal Names are converted to simple Unquals)
	--  (c) by Template Haskell, when TH has generated a unique name
\end{code}


%************************************************************************
%*									*
\subsection{Simple functions}
%*									*
%************************************************************************

\begin{code}
rdrNameModule :: RdrName -> Module
rdrNameModule (Qual m _) = m
rdrNameModule (Orig m _) = m
rdrNameModule (Exact n)  = nameModule n
rdrNameModule (Unqual n) = pprPanic "rdrNameModule" (ppr n)

rdrNameOcc :: RdrName -> OccName
rdrNameOcc (Qual _ occ) = occ
rdrNameOcc (Unqual occ) = occ
rdrNameOcc (Orig _ occ) = occ
rdrNameOcc (Exact name) = nameOccName name

setRdrNameSpace :: RdrName -> NameSpace -> RdrName
-- This rather gruesome function is used mainly by the parser
-- When parsing		data T a = T | T1 Int
-- we parse the data constructors as *types* because of parser ambiguities,
-- so then we need to change the *type constr* to a *data constr*
--
-- The original-name case *can* occur when parsing
-- 		data [] a = [] | a : [a]
-- For the orig-name case we return an unqualified name.
setRdrNameSpace (Unqual occ) ns = Unqual (setOccNameSpace ns occ)
setRdrNameSpace (Qual m occ) ns = Qual m (setOccNameSpace ns occ)
setRdrNameSpace (Orig m occ) ns = Orig m (setOccNameSpace ns occ)
setRdrNameSpace (Exact n)    ns = Orig (nameModule n)
				       (setOccNameSpace ns (nameOccName n))
\end{code}

\begin{code}
	-- These two are the basic constructors
mkRdrUnqual :: OccName -> RdrName
mkRdrUnqual occ = Unqual occ

mkRdrQual :: Module -> OccName -> RdrName
mkRdrQual mod occ = Qual mod occ

mkOrig :: Module -> OccName -> RdrName
mkOrig mod occ = Orig mod occ

---------------
mkDerivedRdrName :: Name -> (OccName -> OccName) -> (RdrName)
mkDerivedRdrName parent mk_occ
  = mkOrig (nameModule parent) (mk_occ (nameOccName parent))

---------------
	-- These two are used when parsing source files
	-- They do encode the module and occurrence names
mkUnqual :: NameSpace -> UserFS -> RdrName
mkUnqual sp n = Unqual (mkOccFS sp n)

mkVarUnqual :: UserFS -> RdrName
mkVarUnqual n = Unqual (mkOccFS varName n)

mkQual :: NameSpace -> (UserFS, UserFS) -> RdrName
mkQual sp (m, n) = Qual (mkModuleFS m) (mkOccFS sp n)

getRdrName :: NamedThing thing => thing -> RdrName
getRdrName name = nameRdrName (getName name)

nameRdrName :: Name -> RdrName
nameRdrName name = Exact name
-- Keep the Name even for Internal names, so that the
-- unique is still there for debug printing, particularly
-- of Types (which are converted to IfaceTypes before printing)

nukeExact :: Name -> RdrName
nukeExact n 
  | isExternalName n = Orig (nameModule n) (nameOccName n)
  | otherwise	     = Unqual (nameOccName n)
\end{code}

\begin{code}
isRdrDataCon rn = isDataOcc (rdrNameOcc rn)
isRdrTyVar   rn = isTvOcc   (rdrNameOcc rn)
isRdrTc      rn = isTcOcc   (rdrNameOcc rn)

isSrcRdrName (Unqual _) = True
isSrcRdrName (Qual _ _) = True
isSrcRdrName _		= False

isUnqual (Unqual _) = True
isUnqual other	    = False

isQual (Qual _ _) = True
isQual _	  = False

isOrig (Orig _ _) = True
isOrig _	  = False

isOrig_maybe (Orig m n) = Just (m,n)
isOrig_maybe _		= Nothing

isExact (Exact _) = True
isExact other	= False

isExact_maybe (Exact n) = Just n
isExact_maybe other	= Nothing
\end{code}


%************************************************************************
%*									*
\subsection{Instances}
%*									*
%************************************************************************

\begin{code}
instance Outputable RdrName where
    ppr (Exact name)   = ppr name
    ppr (Unqual occ)   = ppr occ <+> ppr_name_space occ
    ppr (Qual mod occ) = ppr mod <> dot <> ppr occ <+> ppr_name_space occ
    ppr (Orig mod occ) = ppr mod <> dot <> ppr occ <+> ppr_name_space occ

ppr_name_space occ = ifPprDebug (parens (occNameFlavour occ))

instance OutputableBndr RdrName where
    pprBndr _ n 
	| isTvOcc (rdrNameOcc n) = char '@' <+> ppr n
	| otherwise		 = ppr n

instance Eq RdrName where
    (Exact n1) 	  == (Exact n2)    = n1==n2
	-- Convert exact to orig
    (Exact n1) 	  == r2@(Orig _ _) = nukeExact n1 == r2
    r1@(Orig _ _) == (Exact n2)    = r1 == nukeExact n2

    (Orig m1 o1)  == (Orig m2 o2)  = m1==m2 && o1==o2
    (Qual m1 o1)  == (Qual m2 o2)  = m1==m2 && o1==o2
    (Unqual o1)   == (Unqual o2)   = o1==o2
    r1 == r2 = False

instance Ord RdrName where
    a <= b = case (a `compare` b) of { LT -> True;  EQ -> True;  GT -> False }
    a <	 b = case (a `compare` b) of { LT -> True;  EQ -> False; GT -> False }
    a >= b = case (a `compare` b) of { LT -> False; EQ -> True;  GT -> True  }
    a >	 b = case (a `compare` b) of { LT -> False; EQ -> False; GT -> True  }

	-- Exact < Unqual < Qual < Orig
	-- [Note: Apr 2004] We used to use nukeExact to convert Exact to Orig 
	-- 	before comparing so that Prelude.map == the exact Prelude.map, but 
	--	that meant that we reported duplicates when renaming bindings 
	--	generated by Template Haskell; e.g 
	--	do { n1 <- newName "foo"; n2 <- newName "foo"; 
	--	     <decl involving n1,n2> }
	--	I think we can do without this conversion
    compare (Exact n1) (Exact n2) = n1 `compare` n2
    compare (Exact n1) n2	  = LT

    compare (Unqual _)   (Exact _)    = GT
    compare (Unqual o1)  (Unqual  o2) = o1 `compare` o2
    compare (Unqual _)   _ 	      = LT

    compare (Qual _ _)   (Exact _)    = GT
    compare (Qual _ _)   (Unqual _)   = GT
    compare (Qual m1 o1) (Qual m2 o2) = (o1 `compare` o2) `thenCmp` (m1 `compare` m2) 
    compare (Qual _ _)   (Orig _ _)   = LT

    compare (Orig m1 o1) (Orig m2 o2) = (o1 `compare` o2) `thenCmp` (m1 `compare` m2) 
    compare (Orig _ _)   _	      = GT
\end{code}



%************************************************************************
%*									*
			LocalRdrEnv
%*									*
%************************************************************************

A LocalRdrEnv is used for local bindings (let, where, lambda, case)
It is keyed by OccName, because we never use it for qualified names.

\begin{code}
type LocalRdrEnv = OccEnv Name

emptyLocalRdrEnv = emptyOccEnv

extendLocalRdrEnv :: LocalRdrEnv -> [Name] -> LocalRdrEnv
extendLocalRdrEnv env names
  = extendOccEnvList env [(nameOccName n, n) | n <- names]

lookupLocalRdrEnv :: LocalRdrEnv -> RdrName -> Maybe Name
lookupLocalRdrEnv env (Exact name) = Just name
lookupLocalRdrEnv env (Unqual occ) = lookupOccEnv env occ
lookupLocalRdrEnv env other	   = Nothing

elemLocalRdrEnv :: RdrName -> LocalRdrEnv -> Bool
elemLocalRdrEnv rdr_name env 
  | isUnqual rdr_name = rdrNameOcc rdr_name `elemOccEnv` env
  | otherwise	      = False
\end{code}


%************************************************************************
%*									*
			GlobalRdrEnv
%*									*
%************************************************************************

\begin{code}
type GlobalRdrEnv = OccEnv [GlobalRdrElt]
	-- Keyed by OccName; when looking up a qualified name
	-- we look up the OccName part, and then check the Provenance
	-- to see if the appropriate qualification is valid.  This
	-- saves routinely doubling the size of the env by adding both
	-- qualified and unqualified names to the domain.
	--
	-- The list in the range is reqd because there may be name clashes
	-- These only get reported on lookup, not on construction

	-- INVARIANT: All the members of the list have distinct 
	--	      gre_name fields; that is, no duplicate Names

emptyGlobalRdrEnv = emptyOccEnv

globalRdrEnvElts :: GlobalRdrEnv -> [GlobalRdrElt]
globalRdrEnvElts env = foldOccEnv (++) [] env

data GlobalRdrElt 
  = GRE { gre_name   :: Name,
	  gre_prov   :: Provenance	-- Why it's in scope
    }

instance Outputable GlobalRdrElt where
  ppr gre = ppr name <+> pp_parent (nameParent_maybe name)
		<+> parens (pprNameProvenance gre)
	  where
	    name = gre_name gre
	    pp_parent (Just p) = brackets (text "parent:" <+> ppr p)
	    pp_parent Nothing  = empty

pprGlobalRdrEnv :: GlobalRdrEnv -> SDoc
pprGlobalRdrEnv env
  = vcat (map pp (occEnvElts env))
  where
    pp gres = ppr (nameOccName (gre_name (head gres))) <> colon <+> 
	      vcat [ ppr (gre_name gre) <+> pprNameProvenance gre
		   | gre <- gres]
\end{code}

\begin{code}
lookupGlobalRdrEnv :: GlobalRdrEnv -> OccName -> [GlobalRdrElt]
lookupGlobalRdrEnv env rdr_name = case lookupOccEnv env rdr_name of
					Nothing   -> []
					Just gres -> gres

extendGlobalRdrEnv :: GlobalRdrEnv -> GlobalRdrElt -> GlobalRdrEnv
extendGlobalRdrEnv env gre = extendOccEnv_C add env occ [gre]
  where
    occ = nameOccName (gre_name gre)
    add gres _ = gre:gres

lookupGRE_RdrName :: RdrName -> GlobalRdrEnv -> [GlobalRdrElt]
lookupGRE_RdrName rdr_name env
  = case lookupOccEnv env (rdrNameOcc rdr_name) of
	Nothing   -> []
	Just gres -> pickGREs rdr_name gres

lookupGRE_Name :: GlobalRdrEnv -> Name -> [GlobalRdrElt]
lookupGRE_Name env name
  = [ gre | gre <- lookupGlobalRdrEnv env (nameOccName name),
	    gre_name gre == name ]


pickGREs :: RdrName -> [GlobalRdrElt] -> [GlobalRdrElt]
-- Take a list of GREs which have the right OccName
-- Pick those GREs that are suitable for this RdrName
-- And for those, keep only only the Provenances that are suitable
-- 
-- Consider
--	 module A ( f ) where
--	 import qualified Foo( f )
--	 import Baz( f )
--	 f = undefined
-- Let's suppose that Foo.f and Baz.f are the same entity really.
-- The export of f is ambiguous because it's in scope from the local def
-- and the import.  The lookup of (Unqual f) should return a GRE for
-- the locally-defined f, and a GRE for the imported f, with a *single* 
-- provenance, namely the one for Baz(f).
pickGREs rdr_name gres
  = mapCatMaybes pick gres
  where
    is_unqual = isUnqual rdr_name
    mod	      = rdrNameModule rdr_name

    pick :: GlobalRdrElt -> Maybe GlobalRdrElt
    pick gre@(GRE {gre_prov = LocalDef m}) 	-- Local def
	| is_unqual || m == mod = Just gre
	| otherwise		= Nothing
    pick gre@(GRE {gre_prov = Imported [is]})	-- Single import (efficiency)
	| is_unqual     = if not (is_qual (is_decl is)) then Just gre
						        else Nothing
	| otherwise     = if mod == is_as (is_decl is)  then Just gre
						        else Nothing
    pick gre@(GRE {gre_prov = Imported is})	-- Multiple import
	| null filtered_is = Nothing
	| otherwise	   = Just (gre {gre_prov = Imported filtered_is})
	where
	  filtered_is | is_unqual = filter (not . is_qual    . is_decl) is
		      | otherwise = filter ((== mod) . is_as . is_decl) is

isLocalGRE :: GlobalRdrElt -> Bool
isLocalGRE (GRE {gre_prov = LocalDef _}) = True
isLocalGRE other    		         = False

unQualOK :: GlobalRdrElt -> Bool
-- An unqualifed version of this thing is in scope
unQualOK (GRE {gre_prov = LocalDef _})  = True
unQualOK (GRE {gre_prov = Imported is}) = not (all (is_qual . is_decl) is)

plusGlobalRdrEnv :: GlobalRdrEnv -> GlobalRdrEnv -> GlobalRdrEnv
plusGlobalRdrEnv env1 env2 = plusOccEnv_C (foldr insertGRE) env1 env2

mkGlobalRdrEnv :: [GlobalRdrElt] -> GlobalRdrEnv
mkGlobalRdrEnv gres
  = foldr add emptyGlobalRdrEnv gres
  where
    add gre env = extendOccEnv_C (foldr insertGRE) env 
				 (nameOccName (gre_name gre)) 
				 [gre]

insertGRE :: GlobalRdrElt -> [GlobalRdrElt] -> [GlobalRdrElt]
insertGRE new_g [] = [new_g]
insertGRE new_g (old_g : old_gs)
	| gre_name new_g == gre_name old_g
	= new_g `plusGRE` old_g : old_gs
	| otherwise
	= old_g : insertGRE new_g old_gs

plusGRE :: GlobalRdrElt -> GlobalRdrElt -> GlobalRdrElt
-- Used when the gre_name fields match
plusGRE g1 g2
  = GRE { gre_name = gre_name g1,
	  gre_prov = gre_prov g1 `plusProv` gre_prov g2 }
\end{code}


%************************************************************************
%*									*
			Provenance
%*									*
%************************************************************************

The "provenance" of something says how it came to be in scope.
It's quite elaborate so that we can give accurate unused-name warnings.

\begin{code}
data Provenance
  = LocalDef		-- Defined locally
	Module

  | Imported 				-- Imported
	[ImportSpec]	-- INVARIANT: non-empty

data ImportSpec = ImpSpec { is_decl :: ImpDeclSpec,
			    is_item ::  ImpItemSpec }
		deriving( Eq, Ord )

data ImpDeclSpec	-- Describes a particular import declaration
			-- Shared among all the Provenaces for that decl
  = ImpDeclSpec {
	is_mod      :: Module,	-- 'import Muggle'
				-- Note the Muggle may well not be 
				-- the defining module for this thing!
	is_as       :: Module,	-- 'as M' (or 'Muggle' if there is no 'as' clause)
	is_qual     :: Bool,	-- True <=> qualified (only)
	is_dloc     :: SrcSpan	-- Location of import declaration
    }

data ImpItemSpec  -- Describes import info a particular Name
  = ImpAll		-- The import had no import list, 
			-- or  had a hiding list

  | ImpSome {		-- The import had an import list
	is_explicit :: Bool,
	is_iloc     :: SrcSpan	-- Location of the import item
    }
	-- The is_explicit field is True iff the thing was named 
	-- *explicitly* in the import specs rather 
	-- than being imported as part of a "..." group 
	-- e.g.		import C( T(..) )
	-- Here the constructors of T are not named explicitly; 
	-- only T is named explicitly.

importSpecLoc :: ImportSpec -> SrcSpan
importSpecLoc (ImpSpec decl ImpAll) = is_dloc decl
importSpecLoc (ImpSpec _    item)   = is_iloc item

importSpecModule :: ImportSpec -> Module
importSpecModule is = is_mod (is_decl is)

-- Note [Comparing provenance]
-- Comparison of provenance is just used for grouping 
-- error messages (in RnEnv.warnUnusedBinds)
instance Eq Provenance where
  p1 == p2 = case p1 `compare` p2 of EQ -> True; _ -> False

instance Eq ImpDeclSpec where
  p1 == p2 = case p1 `compare` p2 of EQ -> True; _ -> False

instance Eq ImpItemSpec where
  p1 == p2 = case p1 `compare` p2 of EQ -> True; _ -> False

instance Ord Provenance where
   compare (LocalDef _) (LocalDef _)   	 = EQ
   compare (LocalDef _) (Imported _) 	 = LT
   compare (Imported _ ) (LocalDef _)    = GT
   compare (Imported is1) (Imported is2) = compare (head is1) 
	{- See Note [Comparing provenance] -}	   (head is2)

instance Ord ImpDeclSpec where
   compare is1 is2 = (is_mod is1 `compare` is_mod is2) `thenCmp` 
		     (is_dloc is1 `compare` is_dloc is2)

instance Ord ImpItemSpec where
   compare is1 is2 = is_iloc is1 `compare` is_iloc is2
\end{code}

\begin{code}
plusProv :: Provenance -> Provenance -> Provenance
-- Choose LocalDef over Imported
-- There is an obscure bug lurking here; in the presence
-- of recursive modules, something can be imported *and* locally
-- defined, and one might refer to it with a qualified name from
-- the import -- but I'm going to ignore that because it makes
-- the isLocalGRE predicate so much nicer this way
plusProv (LocalDef m1) (LocalDef m2)     = pprPanic "plusProv" (ppr m1 <+> ppr m2)
plusProv p1@(LocalDef _) p2		 = p1
plusProv p1 		 p2@(LocalDef _) = p2
plusProv (Imported is1)  (Imported is2)  = Imported (is1++is2)

pprNameProvenance :: GlobalRdrElt -> SDoc
-- Print out the place where the name was imported
pprNameProvenance (GRE {gre_name = name, gre_prov = LocalDef _})
  = ptext SLIT("defined at") <+> ppr (nameSrcLoc name)
pprNameProvenance (GRE {gre_name = name, gre_prov = Imported (why:whys)})
  = sep [ppr why, nest 2 (ppr_defn (nameSrcLoc name))]

-- If we know the exact definition point (which we may do with GHCi)
-- then show that too.  But not if it's just "imported from X".
ppr_defn loc | isGoodSrcLoc loc = parens (ptext SLIT("defined at") <+> ppr loc)
	     | otherwise	= empty

instance Outputable ImportSpec where
   ppr imp_spec@(ImpSpec imp_decl _)
     = ptext SLIT("imported from") <+> ppr (is_mod imp_decl) 
	<+> ptext SLIT("at") <+> ppr (importSpecLoc imp_spec)
\end{code}
