polname,schema,table,using_expr,withcheck_expr,roles,cmd
cron_job_policy,cron,job,(username = CURRENT_USER),null,{-},*
cron_job_run_details_policy,cron,job_run_details,(username = CURRENT_USER),null,{-},*
admins can delete any claims,public,claims,"is_event_admin(event_id_for_item(item_id), auth.uid())",null,{-},d
claims_select_by_claimer,public,claims,(auth.uid() = claimer_id),null,{-},r
claims_update_by_claimer,public,claims,(auth.uid() = claimer_id),(auth.uid() = claimer_id),{-},w
claims_update_own,public,claims,(auth.uid() = claimer_id),(auth.uid() = claimer_id),{-},w
delete own claims,public,claims,(claimer_id = auth.uid()),null,{-},d
event_members_select,public,event_members,is_member_of_event(event_id),null,{-},r
admins can delete events,public,events,"is_event_admin(id, auth.uid())",null,{-},d
events: update by admins,public,events,"(EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = events.id) AND (em.user_id = auth.uid()) AND (em.role = 'admin'::member_role))))","(EXISTS ( SELECT 1
   FROM event_members em
  WHERE ((em.event_id = events.id) AND (em.user_id = auth.uid()) AND (em.role = 'admin'::member_role))))",{-},w
insert events when owner is self,public,events,null,(owner_id = auth.uid()),{-},a
owners can delete events,public,events,(owner_id = auth.uid()),null,{-},d
select events for members,public,events,"is_event_member(id, auth.uid())",null,{-},r
select events for owners,public,events,(owner_id = auth.uid()),null,{-},r
creators can delete own items,public,items,(created_by = auth.uid()),null,{-},d
creators can update own items,public,items,(created_by = auth.uid()),(created_by = auth.uid()),{-},w
items_select_visible,public,items,"can_view_list(list_id, auth.uid())",null,{-},r
members can insert items into their event lists,public,items,null,"((auth.role() = 'authenticated'::text) AND (created_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM (lists l
     JOIN event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = auth.uid())))))",{-},a
members can select items in their events,public,items,"(EXISTS ( SELECT 1
   FROM (lists l
     JOIN event_members em ON ((em.event_id = l.event_id)))
  WHERE ((l.id = items.list_id) AND (em.user_id = auth.uid()))))",null,{-},r
le_select,public,list_exclusions,(user_id = auth.uid()),null,{-},r
list_exclusions_insert,public,list_exclusions,null,"(EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_exclusions.list_id) AND (l.created_by = auth.uid()))))",{authenticated},a
list_exclusions_select,public,list_exclusions,"((EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_exclusions.list_id) AND (l.created_by = auth.uid())))) OR (user_id = auth.uid()))",null,{authenticated},r
insert list_recipients by creator,public,list_recipients,null,"(EXISTS ( SELECT 1
   FROM lists l
  WHERE ((l.id = list_recipients.list_id) AND (l.created_by = auth.uid()))))",{-},a
list_recipients_select,public,list_recipients,can_view_list(list_id),null,{-},r
lv_select,public,list_viewers,(user_id = auth.uid()),null,{-},r
lists_select_visible,public,lists,"can_view_list(id, auth.uid())",null,{-},r
profiles are readable by logged in users,public,profiles,(auth.uid() IS NOT NULL),null,{-},r
users can insert their own profile,public,profiles,null,(id = auth.uid()),{-},a
users can update their own profile,public,profiles,(id = auth.uid()),(id = auth.uid()),{-},w
no_client_writes,public,user_plans,false,false,{authenticated},*
read_own_plan,public,user_plans,(auth.uid() = user_id),null,{authenticated},r
user_plans_self,public,user_plans,(user_id = auth.uid()),(user_id = auth.uid()),{-},*