import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Chrome on the same computer: Flask runs on port 5000.
// Android emulator: change this to http://10.0.2.2:5000/api
const String apiBase = 'http://127.0.0.1:5000/api';

void main() => runApp(const FitAiApp());

class FitAiApp extends StatelessWidget {
  const FitAiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FitAI', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4f46e5)), useMaterial3: true),
    home: const AuthScreen(),
  );
}

class Api {
  static String? token;
  static Map<String, String> get headers => {'Content-Type':'application/json', if (token != null) 'Authorization':'Bearer $token'};
  static Future<dynamic> request(String method, String path, {Map<String,dynamic>? body}) async {
    final uri = Uri.parse('$apiBase$path');
    late http.Response response;
    if (method == 'GET') { response = await http.get(uri, headers: headers); }
    else if (method == 'POST') { response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {})); }
    else { throw Exception('Unsupported request'); }
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = response.body; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data is Map ? (data['error'] ?? data['message'] ?? 'Request failed') : 'Request failed (${response.statusCode})');
    }
    return data;
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final name = TextEditingController(), email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? error;
  Future<void> submit() async {
    setState(() {busy=true; error=null;});
    try {
      final data = await Api.request('POST', register ? '/register' : '/login', body: {
        if (register) 'name': name.text.trim(), 'email': email.text.trim(), 'password': password.text,
      });
      if (!mounted) return;
      if (register) { setState(() {register=false; busy=false;}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Now log in.'))); return; }
      Api.token = data['token'] as String?;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => Dashboard(name: (data['name'] ?? 'Fitness buddy').toString())));
    } catch (e) { setState(() {error=e.toString().replaceFirst('Exception: ', '');}); }
    finally { if (mounted) setState(() {busy=false;}); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.fitness_center, size: 64, color: Color(0xff4f46e5)), const SizedBox(height: 12),
      const Text('FitAI', textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
      const Text('Your fitness journey starts here', textAlign: TextAlign.center), const SizedBox(height: 28),
      Text(register ? 'Create account' : 'Welcome back', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 16),
      if (register) ...[TextField(controller: name, decoration: const InputDecoration(labelText:'Full name', border: OutlineInputBorder())), const SizedBox(height:12)],
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText:'Email', border: OutlineInputBorder())), const SizedBox(height:12),
      TextField(controller: password, obscureText:true, decoration: const InputDecoration(labelText:'Password (at least 8 characters)', border: OutlineInputBorder())),
      if (error != null) Padding(padding: const EdgeInsets.only(top:12), child: Text(error!, style: const TextStyle(color:Colors.red))),
      const SizedBox(height:18), FilledButton(onPressed: busy ? null : submit, child: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Please wait...' : register ? 'Register' : 'Login'))),
      TextButton(onPressed: () => setState(() {register=!register; error=null;}), child: Text(register ? 'Already have an account? Login' : 'New to FitAI? Create account')),
      const SizedBox(height:12), const Text('Connects to your local Flask + MySQL backend.', textAlign: TextAlign.center, style: TextStyle(color:Colors.grey)),
    ])))),
  );
}

class Dashboard extends StatefulWidget {
  final String name;
  const Dashboard({super.key, required this.name});
  @override State<Dashboard> createState() => _DashboardState();
}
class _DashboardState extends State<Dashboard> {
  int tab = 0; bool busy = true; String? error;
  List<dynamic> workouts=[], plan=[], progress=[];
  Map<String,dynamic> summary={'completed_workouts':0,'total_minutes':0};
  @override void initState(){super.initState(); load();}
  Future<void> load() async {
    setState(() {busy=true; error=null;});
    try {
      final results = await Future.wait([Api.request('GET','/workouts'),Api.request('GET','/me/workouts'),Api.request('GET','/me/progress'),Api.request('GET','/me/progress/summary')]);
      workouts=results[0] as List; plan=results[1] as List; progress=results[2] as List; summary=Map<String,dynamic>.from(results[3] as Map);
    } catch(e) {error=e.toString().replaceFirst('Exception: ','');}
    finally {if(mounted)setState(()=>busy=false);}
  }
  Future<void> complete(dynamic workout) async {
    final duration=workout['duration'] is int ? workout['duration'] as int : int.tryParse('${workout['duration']}') ?? 1;
    try {await Api.request('POST','/me/progress',body:{'workout_id':workout['id'],'duration_minutes':duration}); await load(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Workout completed! Progress saved.')));}
    catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
  }
  Future<void> addToPlan(dynamic workout) async {
    try {await Api.request('POST','/me/workouts',body:{'workout_id':workout['id']}); await load(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Added to your plan!')));}
    catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
  }
  @override Widget build(BuildContext context) {
    final titles=['Home','Workouts','My Plan','Progress'];
    return Scaffold(appBar:AppBar(title:Text('FitAI · ${titles[tab]}'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh),tooltip:'Refresh')]),
      body: busy ? const Center(child:CircularProgressIndicator()) : error != null ? Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(error!,textAlign:TextAlign.center),const SizedBox(height:12),FilledButton(onPressed:load,child:const Text('Try again'))]))) : IndexedStack(index:tab,children:[homePage(), listPage(workouts, showAdd:true), listPage(plan, showAdd:false), progressPage()]),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.fitness_center),label:'Workouts'),NavigationDestination(icon:Icon(Icons.event_note),label:'My Plan'),NavigationDestination(icon:Icon(Icons.insights),label:'Progress')]),
    );
  }
  Widget homePage()=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(18),children:[Text('Hello, ${widget.name} 👋',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Small steps make strong habits.'),const SizedBox(height:22),Row(children:[Expanded(child:statCard('Completed', '${summary['completed_workouts']??0}',Icons.check_circle_outline)),const SizedBox(width:12),Expanded(child:statCard('Minutes', '${summary['total_minutes']??0}',Icons.timer_outlined))]),const SizedBox(height:24),Text('Suggested workouts',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),...workouts.take(3).map((w)=>workoutCard(w,showAdd:true))]));
  Widget statCard(String label,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(height:10),Text(value,style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold)),Text(label)])));
  Widget listPage(List<dynamic> items,{required bool showAdd})=>RefreshIndicator(onRefresh:load,child:items.isEmpty?ListView(children:[const SizedBox(height:100),const Center(child:Text('No workouts here yet.'))]):ListView(padding:const EdgeInsets.all(12),children:items.map((w)=>workoutCard(w,showAdd:showAdd)).toList()));
  Widget workoutCard(dynamic w,{required bool showAdd})=>Card(margin:const EdgeInsets.symmetric(vertical:6),child:ListTile(leading:CircleAvatar(child:const Icon(Icons.fitness_center)),title:Text('${w['name']??w['workout_name']??'Workout'}',style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('${w['duration']??w['duration_minutes']??0} minutes'),trailing:showAdd?IconButton(tooltip:'Add to plan',icon:const Icon(Icons.add_circle_outline),onPressed:()=>addToPlan(w)):IconButton(tooltip:'Mark completed',icon:const Icon(Icons.check_circle_outline),onPressed:()=>complete(w))));
  Widget progressPage()=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(12),children:[statCard('Completed workouts','${summary['completed_workouts']??0}',Icons.check_circle),statCard('Total exercise minutes','${summary['total_minutes']??0}',Icons.timer),const SizedBox(height:12),Text('Recent activity',style:Theme.of(context).textTheme.titleLarge),if(progress.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('Complete a workout to see your history.')), ...progress.map((p)=>ListTile(leading:const Icon(Icons.check_circle,color:Colors.green),title:Text('${p['workout_name']}'),subtitle:Text('${p['duration_minutes']} minutes · ${p['completed_at']}')))]));
}
