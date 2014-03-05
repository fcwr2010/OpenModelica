#include "stdafx.h"
#include "FactoryExport.h"


#include <Solver/SolverDefaultImplementation.h>
#include <Solver/SolverSettings.h>
#include <SimulationSettings/IGlobalSettings.h>

#include <Math/Constants.h>

SolverDefaultImplementation::SolverDefaultImplementation(IMixedSystem* system, ISolverSettings* settings)
: _system                        (system)
, _settings                        (settings)

, _tInit                (0.0)
, _tCurrent                (0.0)
, _tEnd                    (0.0)
, _tLastSuccess            (0.0)
, _tLastUnsucess        (0.0)
, _tLargeStep            (0.0)
, _h                    (0.0)

//, _firstCall            (true)
, _firstStep            (true)

, _totStps                (0)
, _accStps                (0)
, _rejStps                (0)
, _zeroStps                (0)
, _zeros                (0)

, _zeroStatus                  (ISolver::UNCHANGED_SIGN)
, _zeroValInit                  (NULL)
, _dimZeroFunc                  (0)
, _zeroVal                        (NULL)
, _zeroValLastSuccess      (NULL)
, _events                        (NULL)

, _outputCommand            (IWriteOutput::WRITEOUT)

{
   _state_selection = boost::shared_ptr<SystemStateSelection>(new SystemStateSelection(system));
}
SolverDefaultImplementation::~SolverDefaultImplementation()
{
    if(_zeroVal)
        delete [] _zeroVal;
    if(_zeroValInit)
        delete [] _zeroValInit;
    if(_zeroValLastSuccess)
        delete [] _zeroValLastSuccess;
    if(_events)
        delete [] _events;
    
}

        void SolverDefaultImplementation::setStartTime(const double& t)
    {
        _tCurrent = t;
    };

     void SolverDefaultImplementation::setEndTime(const double& t)
    {
        _tEnd = t;
    };

     void SolverDefaultImplementation::setInitStepSize(const double& h)
    {
        _h = h;
    };



    const ISolver::SOLVERSTATUS SolverDefaultImplementation::getSolverStatus()
    {
        return _solverStatus;
    };
  
bool SolverDefaultImplementation::stateSelection()
{
   return _state_selection->stateSelection(1);
} 
void SolverDefaultImplementation::initialize()
{
    IContinuous* continous_system = dynamic_cast<IContinuous*>(_system);
    IEvent* event_system =  dynamic_cast<IEvent*>(_system);
    ITime* timeevent_system = dynamic_cast<ITime*>(_system);
  IWriteOutput* writeoutput_system = dynamic_cast<IWriteOutput*>(_system);
    // Set current start time to the system
    timeevent_system->setTime(_tCurrent);
    
   
    

    //// Write out head line
    //if (_outputStream)
    //{
    //    // Write head line (step time step size) into output stream
    //    *_outputStream << "step\t time\t h";
    //
    //    // Prompt system to write out its results
    //    _system->writeOutput(IMixedSystem::HEAD_LINE);

    //    // Write a line break into output stream
    //    *_outputStream << std::endl;
    //}
   writeoutput_system->writeOutput(IWriteOutput::HEAD_LINE);

    // Allocate array with values of zero functions
    if (_dimZeroFunc != event_system->getDimZeroFunc())
    {
        // Number (dimension) of zero functions
        _dimZeroFunc = event_system->getDimZeroFunc();

        if(_zeroVal)
            delete [] _zeroVal;
        if(_zeroValInit)
            delete [] _zeroValInit;
        if(_zeroValLastSuccess)
            delete [] _zeroValLastSuccess;
        if(_events)
            delete [] _events;

        _zeroVal                  = new double[_dimZeroFunc];
        _zeroValLastSuccess      = new double[_dimZeroFunc];
        _events                        = new bool[_dimZeroFunc];
        _zeroValInit                  = new double[_dimZeroFunc];
       
        event_system->getZeroFunc(_zeroVal);
        memcpy(_zeroValLastSuccess,_zeroVal,_dimZeroFunc*sizeof(double));
        memcpy(_zeroValInit,_zeroVal,_dimZeroFunc*sizeof(double));
        memset(_events,false,_dimZeroFunc*sizeof(bool));
    }

     // Set flags
    _firstCall                  = true; 
    _firstStep                  = true;
 

    // Reset counter
    _totStps     = 0;
    _accStps     = 0;
    _rejStps    = 0;
    _zeroStps    = 0;
    _zeros        = 0;

    // Set initial step size
    //_h = _settings->_globalSettings->_hOutput;
}

void SolverDefaultImplementation::setZeroState()
{

        // Reset Zero-State
    _zeroStatus = ISolver::UNCHANGED_SIGN;;
    
    // Alle Elemente im ZeroFunction-Array durchgehen
    for (int i=0; i<_dimZeroFunc; ++i)
    {
        // Überprüfung auf Vorzeichenwechsel
        if ((_zeroVal[i] < 0 && _zeroValLastSuccess[i] > 0) || (_zeroVal[i] > 0 && _zeroValLastSuccess[i] < 0))
        {
                // Vorzeichenwechsel, aber Eintrag ist größer (oder kleiner) als Toleranzbereich
                _zeroStatus = ISolver::EQUAL_ZERO;

                // Rest ZeroSign
                _events[i] = true;

                // Zeitpunkt des letzten verworfenen Schrittes abspeichern
                _tLastUnsucess = _tCurrent;
                break;
        }
        else
            _events[i] = false;
    }

}



void SolverDefaultImplementation::writeToFile(const int& stp, const double& t, const double& h)
{
   IWriteOutput* writeoutput_system = dynamic_cast<IWriteOutput*>(_system);
    //if (_outputStream && _settings->_globalSettings->_resultsOutput)
    //{
    //    // Reset curser within output stream to last valid position (before zero crossing)
    //    if(_outputCommand & IContinuous::RESET)
    //        if(stp == 1)
    //            _outputStream->seekp(_curserPosition);

    //    if(_outputCommand & IContinuous::WRITE)
    //    {
    //        // In the first step, tell (inital) curser position within output stream
    //        if(stp == 1)
    //            _curserPosition = _outputStream->tellp();

    //        // Write current step, time and step size into output stream
    //        *_outputStream << stp << "\t" << t << "\t" << h;

    //        // Write out output stream
    //        _system->writeOutput(_outputCommand);
    //
    //        // Write a line break into output stream
    //        *_outputStream << std::endl;
    //    }
    //}
    
    if(_outputCommand & IWriteOutput::WRITEOUT)
    {
        writeoutput_system->writeOutput(_outputCommand);
      
    }
}
void SolverDefaultImplementation::updateEventState()
{
    dynamic_cast<IEvent*>(_system)->getZeroFunc(_zeroVal);
    setZeroState();
    if (_zeroStatus == ISolver::ZERO_CROSSING)       // An event triggered an other event
    {
        _tLastSuccess = _tCurrent;         // Concurrently occured events are in the time tollerance
        setZeroState();                     // Upate status of events vector
    }
}
